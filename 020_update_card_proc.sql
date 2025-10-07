CREATE OR REPLACE PROCEDURE update_card_proc(
    p_card_id INT,
    p_card_number VARCHAR(16) DEFAULT NULL,
    p_expiry_month SMALLINT DEFAULT NULL,
    p_expiry_year SMALLINT DEFAULT NULL,
    p_ccv VARCHAR(3) DEFAULT NULL,
    p_limit_amount DECIMAL(13,3) DEFAULT NULL,
    p_current_debt DECIMAL(13,3) DEFAULT NULL,
    p_balance DECIMAL(13,3) DEFAULT NULL,
    p_status VARCHAR(20) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Mevcut kart bilgileri
    p_deleted_at_card TIMESTAMP;
    p_current_card_number VARCHAR(16);
    p_current_status VARCHAR(20);
    p_current_limit DECIMAL(13,3);
    p_current_debt DECIMAL(13,3);
    p_current_balance DECIMAL(13,3);
    
    -- İlişkili bilgiler
    p_customer_id INT;
    p_account_id INT;
    p_card_type_id INT;
    p_card_type_name VARCHAR(50);
    p_customer_deleted_at TIMESTAMP;
    p_account_deleted_at TIMESTAMP;
    p_account_status VARCHAR(20);
    p_customer_risk_limit DECIMAL(13,3);
    
    -- Status değişikliği için
    p_active_account_cards_count INT;
BEGIN
    -- 1. INPUT VALIDASYONU
    IF p_card_id IS NULL OR p_card_id <= 0 THEN
        RAISE EXCEPTION 'Geçersiz kart ID: %', p_card_id;
    END IF;
    
    -- Tarih validasyonları
    IF p_expiry_month IS NOT NULL AND (p_expiry_month < 1 OR p_expiry_month > 12) THEN
        RAISE EXCEPTION 'Geçersiz ay: % (1-12 arası olmalı)', p_expiry_month;
    END IF;
    
    IF p_expiry_year IS NOT NULL AND p_expiry_year < EXTRACT(YEAR FROM CURRENT_DATE) THEN
        RAISE EXCEPTION 'Geçersiz yıl: % (gelecek tarih olmalı)', p_expiry_year;
    END IF;
    
    -- Kart numarası format kontrolü
    IF p_card_number IS NOT NULL AND (LENGTH(TRIM(p_card_number)) != 16 OR p_card_number !~ '^[0-9]+$') THEN
        RAISE EXCEPTION 'Kart numarası 16 haneli rakam olmalıdır: %', p_card_number;
    END IF;
    
    -- CCV kontrolü
    IF p_ccv IS NOT NULL AND (LENGTH(TRIM(p_ccv)) != 3 OR p_ccv !~ '^[0-9]+$') THEN
        RAISE EXCEPTION 'CCV 3 haneli rakam olmalıdır: %', p_ccv;
    END IF;
    
    -- Status kontrolü
    IF p_status IS NOT NULL AND p_status NOT IN ('ACTIVE', 'INACTIVE', 'SUSPENDED') THEN
        RAISE EXCEPTION 'Geçersiz status: %, sadece ACTIVE, INACTIVE veya SUSPENDED olabilir', p_status;
    END IF;
    
    -- 2. KART BİLGİLERİNİ AL (Tek sorgu ile performance)
    SELECT 
        c.deleted_at, c.card_number, c.status, c.limit_amount, c.current_debt, c.balance,
        c.customer_id, c.account_id, c.card_type_id, ct.type_name
    INTO 
        p_deleted_at_card, p_current_card_number, p_current_status, p_current_limit, 
        p_current_debt, p_current_balance, p_customer_id, p_account_id, p_card_type_id, p_card_type_name
    FROM card c
    JOIN card_type ct ON c.card_type_id = ct.card_type_id
    WHERE c.card_id = p_card_id;
    
    -- 3. KART VARLIK KONTROLÜ
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kart bulunamadı (ID: %)', p_card_id;
    END IF;
    
    IF p_deleted_at_card IS NOT NULL THEN
        RAISE EXCEPTION 'Silinmiş bir kart güncellenemez (ID: %)', p_card_id;
    END IF;
    
    -- 4. MÜŞTERİ KONTROLÜ
    SELECT deleted_at, risk_limit INTO p_customer_deleted_at, p_customer_risk_limit
    FROM customer
    WHERE customer_id = p_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Karta ait müşteri bulunamadı (Customer ID: %)', p_customer_id;
    END IF;
    
    IF p_customer_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Silinmiş müşteriye ait kart güncellenemez (Customer ID: %)', p_customer_id;
    END IF;
    
    -- 5. HESAP KONTROLÜ (Sadece ACCOUNT kartları için)
    IF p_card_type_name = 'ACCOUNT' AND p_account_id IS NOT NULL THEN
        SELECT deleted_at, status INTO p_account_deleted_at, p_account_status
        FROM account
        WHERE account_id = p_account_id AND customer_id = p_customer_id;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Karta ait hesap bulunamadı (Account ID: %)', p_account_id;
        END IF;
        
        IF p_account_deleted_at IS NOT NULL THEN
            RAISE EXCEPTION 'Silinmiş hesaba ait kart güncellenemez (Account ID: %)', p_account_id;
        END IF;
        
        IF p_account_status != 'ACTIVE' THEN
            RAISE EXCEPTION 'Pasif hesaba ait kart güncellenemez. Hesap durumu: %', p_account_status;
        END IF;
    END IF;
    
    -- 6. KART NUMARASI TEKRARLILık KONTROLÜ
    IF p_card_number IS NOT NULL AND p_card_number != p_current_card_number THEN
        IF EXISTS (
            SELECT 1 FROM card 
            WHERE card_number = p_card_number AND deleted_at IS NULL AND card_id != p_card_id
        ) THEN
            RAISE EXCEPTION 'Bu kart numarası zaten başka bir karta ait: %', p_card_number;
        END IF;
    END IF;
    
    -- 7. KART TİPİNE ÖZEL KONTROLLER
    IF p_card_type_name = 'ACCOUNT' THEN
        -- ACCOUNT kartları için limit ve debt güncellenemez
        IF p_limit_amount IS NOT NULL THEN
            RAISE EXCEPTION 'ACCOUNT kartlarında limit güncellenemez';
        END IF;
        IF p_current_debt IS NOT NULL THEN
            RAISE EXCEPTION 'ACCOUNT kartlarında current_debt güncellenemez';
        END IF;
        
        -- Bakiye kontrolü
        IF p_balance IS NOT NULL AND p_balance < 0 THEN
            RAISE EXCEPTION 'ACCOUNT kart bakiyesi negatif olamaz: %', p_balance;
        END IF;
        
    ELSIF p_card_type_name = 'CREDIT' THEN
        -- CREDIT kartları için balance güncellenemez
        IF p_balance IS NOT NULL THEN
            RAISE EXCEPTION 'CREDIT kartlarında balance güncellenemez';
        END IF;
        
        -- Limit kontrolü
        IF p_limit_amount IS NOT NULL THEN
            IF p_limit_amount <= 0 THEN
                RAISE EXCEPTION 'CREDIT kart limiti pozitif olmalıdır: %', p_limit_amount;
            END IF;
            IF p_limit_amount > p_customer_risk_limit THEN
                RAISE EXCEPTION 'CREDIT kart limiti (%) risk limitini (%) aşamaz', p_limit_amount, p_customer_risk_limit;
            END IF;
        END IF;
        
        -- Borç kontrolü
        IF p_current_debt IS NOT NULL THEN
            IF p_current_debt < 0 THEN
                RAISE EXCEPTION 'CREDIT kart borcu negatif olamaz: %', p_current_debt;
            END IF;
            -- Yeni limit varsa onu kullan, yoksa mevcut limiti kullan
            IF p_current_debt > COALESCE(p_limit_amount, p_current_limit) THEN
                RAISE EXCEPTION 'CREDIT kart borcu (%) limitten (%) fazla olamaz', 
                               p_current_debt, COALESCE(p_limit_amount, p_current_limit);
            END IF;
        END IF;
    END IF;
    
    -- 8. ACCOUNT KART AKTİFLİK KONTROLÜ
    IF p_card_type_name = 'ACCOUNT' AND p_status IS NOT NULL AND p_status = 'ACTIVE' AND p_current_status != 'ACTIVE' THEN
        -- ACCOUNT kartını aktif yapmaya çalışıyor
        SELECT COUNT(*) INTO p_active_account_cards_count
        FROM card c
        JOIN card_type ct ON c.card_type_id = ct.card_type_id
        WHERE c.account_id = p_account_id 
          AND ct.type_name = 'ACCOUNT'
          AND c.status = 'ACTIVE'
          AND c.deleted_at IS NULL
          AND c.card_id != p_card_id; -- Mevcut kartı hariç tut
        
        IF p_active_account_cards_count > 0 THEN
            RAISE EXCEPTION 'Bu hesapta zaten % aktif ACCOUNT kartı var. Önce diğerlerini pasif yapın.', p_active_account_cards_count;
        END IF;
    END IF;
    
    -- 9. SON KULLANMA TARİHİ KONTROLÜ (Tarih güncelleniyorsa)
    IF (p_expiry_year IS NOT NULL OR p_expiry_month IS NOT NULL) THEN
        -- Mevcut değerleri al
        DECLARE
            final_year SMALLINT := COALESCE(p_expiry_year, (SELECT expiry_year FROM card WHERE card_id = p_card_id));
            final_month SMALLINT := COALESCE(p_expiry_month, (SELECT expiry_month FROM card WHERE card_id = p_card_id));
        BEGIN
            IF final_year < EXTRACT(YEAR FROM CURRENT_DATE) OR 
               (final_year = EXTRACT(YEAR FROM CURRENT_DATE) AND final_month < EXTRACT(MONTH FROM CURRENT_DATE)) THEN
                RAISE EXCEPTION 'Kart son kullanma tarihi geçmiş olamaz: %/%', final_month, final_year;
            END IF;
        END;
    END IF;
    
    -- 10. GÜNCELLEME İŞLEMİ
    UPDATE card
    SET 
        card_number = COALESCE(p_card_number, card_number),
        expiry_month = COALESCE(p_expiry_month, expiry_month),
        expiry_year = COALESCE(p_expiry_year, expiry_year),
        ccv = COALESCE(p_ccv, ccv),
        limit_amount = CASE 
            WHEN p_card_type_name = 'ACCOUNT' THEN NULL 
            ELSE COALESCE(p_limit_amount, limit_amount) 
        END,
        current_debt = CASE 
            WHEN p_card_type_name = 'ACCOUNT' THEN NULL 
            ELSE COALESCE(p_current_debt, current_debt) 
        END,
        balance = CASE 
            WHEN p_card_type_name = 'CREDIT' THEN NULL 
            ELSE COALESCE(p_balance, balance) 
        END,
        status = COALESCE(p_status, status),
        updated_at = CURRENT_TIMESTAMP
    WHERE card_id = p_card_id;
    
    RAISE NOTICE 'Kart başarıyla güncellendi - ID: %, Tip: %, Status: %', 
                 p_card_id, p_card_type_name, COALESCE(p_status, p_current_status);
                 
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Kart güncelleme başarısız: %', SQLERRM;
END;
$$;