CREATE OR REPLACE PROCEDURE create_card_proc(
    p_customer_id INT,
    p_account_id INT,
    p_card_type_id INT,
    p_card_number VARCHAR(16),  
    p_expiry_month SMALLINT,
    p_expiry_year SMALLINT,
    p_ccv VARCHAR(3),          
    p_limit_amount DECIMAL,
    p_current_debt DECIMAL,
    p_balance DECIMAL,
    p_status VARCHAR DEFAULT 'ACTIVE'
)
LANGUAGE plpgsql
AS $$
DECLARE
    p_customer_deleted TIMESTAMP;
    p_account_deleted_at TIMESTAMP;
    p_card_type_name TEXT;
    p_customer_risk_limit DECIMAL;
    p_new_card_id INT;
BEGIN
    -- 1. Input validasyonları
    IF p_card_number IS NULL OR LENGTH(TRIM(p_card_number)) = 0 THEN
        RAISE EXCEPTION 'Kart numarası boş olamaz';
    END IF;
    
    IF p_expiry_month < 1 OR p_expiry_month > 12 THEN
        RAISE EXCEPTION 'Geçersiz ay: % (1-12 arası olmalı)', p_expiry_month;
    END IF;
    
    IF p_expiry_year < EXTRACT(YEAR FROM CURRENT_DATE) THEN
        RAISE EXCEPTION 'Geçersiz yıl: % (gelecek tarih olmalı)', p_expiry_year;
    END IF;
    
    -- Son kullanma tarihi kontrolü
    IF p_expiry_year < EXTRACT(YEAR FROM CURRENT_DATE) OR 
       (p_expiry_year = EXTRACT(YEAR FROM CURRENT_DATE) AND 
        p_expiry_month < EXTRACT(MONTH FROM CURRENT_DATE)) THEN
        RAISE EXCEPTION 'Kart son kullanma tarihi geçmiş olamaz: %/%', p_expiry_month, p_expiry_year;
    END IF;
    
    -- 2. Müşteri kontrolü 
    SELECT deleted_at, risk_limit INTO p_customer_deleted, p_customer_risk_limit
    FROM customer
    WHERE customer_id = p_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Böyle bir müşteri yok: %', p_customer_id;
    ELSIF p_customer_deleted IS NOT NULL THEN
        RAISE EXCEPTION 'Müşteri silinmiş, kart ekleyemezsiniz: %', p_customer_id;
    END IF;
    
    -- 3. Kart numarası tekrar kontrolü
    IF EXISTS (
        SELECT 1
        FROM card
        WHERE card_number = p_card_number AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Bu kart numarası zaten kayıtlı: %', p_card_number;
    END IF;
    
    -- 4. Card type kontrolü ve alan kısıtlamaları
    SELECT type_name INTO p_card_type_name
    FROM card_type
    WHERE card_type_id = p_card_type_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Geçersiz card_type_id: %', p_card_type_id;
    END IF;
    
    IF p_card_type_name = 'ACCOUNT' THEN
        -- Account kart kontrolleri
        IF p_account_id IS NULL THEN
            RAISE EXCEPTION 'ACCOUNT kart için account_id zorunludur';
        END IF;
        
        -- Account var mı ve silinmiş mi kontrol et
        SELECT deleted_at INTO p_account_deleted_at
        FROM account
        WHERE account_id = p_account_id AND customer_id = p_customer_id;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Bu müşteriye ait böyle bir hesap bulunamadı: %', p_account_id;
        ELSIF p_account_deleted_at IS NOT NULL THEN
            RAISE EXCEPTION 'Bu hesap silinmiş, kart eklenemez: %', p_account_id;
        END IF;
        
        -- ACCOUNT kart için limit ve debt NULL olmalı, balance set edilebilir
        p_limit_amount := NULL;
        p_current_debt := NULL;
        IF p_balance IS NULL THEN
            p_balance := 0; -- Varsayılan bakiye
        END IF;
        
    ELSIF p_card_type_name = 'CREDIT' THEN
        -- Credit kart kontrolleri
        p_account_id := NULL;  -- Credit kartlarda account_id NULL
        p_balance := NULL;     -- Credit kartlarda balance NULL
        
        IF p_limit_amount IS NULL OR p_limit_amount <= 0 THEN
            RAISE EXCEPTION 'CREDIT kart için pozitif limit zorunludur';
        ELSIF p_limit_amount > p_customer_risk_limit THEN
            RAISE EXCEPTION 'CREDIT kart limiti (%) risk limitinden (%) fazla olamaz', p_limit_amount, p_customer_risk_limit;
        END IF;
        
        -- Current debt başlangıç değeri
        IF p_current_debt IS NULL THEN
            p_current_debt := 0;
        ELSIF p_current_debt < 0 THEN
            RAISE EXCEPTION 'Current debt negatif olamaz: %', p_current_debt;
        ELSIF p_current_debt > p_limit_amount THEN
            RAISE EXCEPTION 'Current debt (%) limitten (%) fazla olamaz', p_current_debt, p_limit_amount;
        END IF;
        
    ELSE
        RAISE EXCEPTION 'Tanımlanmamış kart tipi: %', p_card_type_name;
    END IF;
    
    -- 5. Status kontrolü
    IF p_status IS NULL THEN
        IF p_card_type_name = 'ACCOUNT' THEN
            -- Account için: hesapta aktif kart var mı kontrol et
            IF EXISTS (
                SELECT 1 
                FROM card c
                JOIN card_type ct ON c.card_type_id = ct.card_type_id
                WHERE c.account_id = p_account_id 
                  AND ct.type_name = 'ACCOUNT'
                  AND c.status = 'ACTIVE'
                  AND c.deleted_at IS NULL
            ) THEN
                -- Zaten aktif ACCOUNT kartı var, yeni kartı INACTIVE yap
                p_status := 'INACTIVE';
                RAISE NOTICE 'Bu hesapta zaten aktif bir ACCOUNT kartı bulunduğu için yeni kart INACTIVE olarak oluşturuldu';
            ELSE
                -- Aktif ACCOUNT kartı yok, yeni kartı ACTIVE yap
                p_status := 'ACTIVE';
            END IF;
        ELSE
            -- CREDIT kart için varsayılan ACTIVE
            p_status := 'ACTIVE';
        END IF;
    ELSIF p_status NOT IN ('ACTIVE', 'INACTIVE', 'SUSPENDED') THEN
        RAISE EXCEPTION 'Geçersiz status: %, sadece ACTIVE, INACTIVE veya SUSPENDED olabilir', p_status;
    END IF;
    
    -- ACCOUNT kart için ek status kontrolü
    IF p_card_type_name = 'ACCOUNT' AND p_status = 'ACTIVE' THEN
        -- Kullanıcı manuel olarak ACTIVE yapmaya çalışıyorsa kontrol et
        IF EXISTS (
            SELECT 1 
            FROM card c
            JOIN card_type ct ON c.card_type_id = ct.card_type_id
            WHERE c.account_id = p_account_id 
              AND ct.type_name = 'ACCOUNT'
              AND c.status = 'ACTIVE'
              AND c.deleted_at IS NULL
        ) THEN
            RAISE EXCEPTION 'Bu hesapta zaten aktif bir ACCOUNT kartı bulunmaktadır. Önce mevcut kartı pasif yapın veya yeni kartı INACTIVE olarak oluşturun.';
        END IF;
    END IF;
    
    -- 6. CCV kontrolü
    IF p_ccv IS NULL OR LENGTH(TRIM(p_ccv)) NOT IN (3) THEN
        RAISE EXCEPTION 'CCV 3 haneli olmalıdır';
    END IF;
    
    -- 7. Insert işlemi
    INSERT INTO card(
        customer_id, account_id, card_type_id, card_number, expiry_month, expiry_year, 
        ccv, limit_amount, current_debt, balance, status
    )
    VALUES (
        p_customer_id, p_account_id, p_card_type_id, p_card_number, p_expiry_month, p_expiry_year,
        p_ccv, p_limit_amount, p_current_debt, p_balance, p_status
    )
    RETURNING card_id INTO p_new_card_id;
    
    RAISE NOTICE 'Kart başarıyla eklendi - ID: %, Numara: %, Tip: %, Status: %', 
                 p_new_card_id, p_card_number, p_card_type_name, p_status;
                 
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Kart oluşturma başarısız: %', SQLERRM;
END;
$$;