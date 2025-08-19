CREATE OR REPLACE PROCEDURE update_account_proc(
    p_account_id INT,
    p_iban CHAR(26) DEFAULT NULL,
    p_account_name VARCHAR(50) DEFAULT NULL,
    p_status VARCHAR(20) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Mevcut hesap bilgileri
    p_deleted_at_account TIMESTAMP;
    p_customer_id INT;
    p_current_iban CHAR(26);
    p_current_status VARCHAR(20);
    p_current_account_name VARCHAR(50);
    
    -- Müşteri bilgileri
    p_deleted_at_customer TIMESTAMP;
    
    -- Kart kontrolleri için
    p_active_cards_count INT;
    p_total_cards_count INT;
BEGIN
    -- 1. INPUT VALIDASYONU
    IF p_account_id IS NULL OR p_account_id <= 0 THEN
        RAISE EXCEPTION 'Geçersiz hesap ID: %', p_account_id;
    END IF;    
    
    -- Hesap adı kontrolü (eğer verilmişse)
    IF p_account_name IS NOT NULL THEN
        IF LENGTH(TRIM(p_account_name)) = 0 THEN
            RAISE EXCEPTION 'Hesap adı boş olamaz';
        END IF;
        
        IF LENGTH(TRIM(p_account_name)) < 3 THEN
            RAISE EXCEPTION 'Hesap adı en az 3 karakter olmalıdır: %', p_account_name;
        END IF;
        
        
    END IF;
    
    -- Status kontrolü (eğer verilmişse)
    IF p_status IS NOT NULL AND p_status NOT IN ('ACTIVE', 'INACTIVE', 'SUSPENDED') THEN
        RAISE EXCEPTION 'Geçersiz status: %, sadece ACTIVE, INACTIVE veya SUSPENDED olabilir', p_status;
    END IF;
    
    -- 2. HESAP VARLIK KONTROLÜ
    SELECT deleted_at, customer_id, iban, status, account_name
    INTO p_deleted_at_account, p_customer_id, p_current_iban, p_current_status, p_current_account_name
    FROM account
    WHERE account_id = p_account_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Hesap bulunamadı (ID: %)', p_account_id;
    END IF;
    
    IF p_deleted_at_account IS NOT NULL THEN
        RAISE EXCEPTION 'Silinmiş bir hesap güncellenemez (ID: %)', p_account_id;
    END IF;
    
    -- 3. MÜŞTERİ KONTROLÜ
    SELECT deleted_at INTO p_deleted_at_customer
    FROM customer
    WHERE customer_id = p_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Hesaba ait müşteri bulunamadı (Customer ID: %)', p_customer_id;
    END IF;
    
    IF p_deleted_at_customer IS NOT NULL THEN
        RAISE EXCEPTION 'Silinmiş müşteriye ait hesap güncellenemez (Customer ID: %)', p_customer_id;
    END IF;
    
    -- 4. IBAN TEKRARLILık KONTROLÜ
    IF p_iban IS NOT NULL AND p_iban != p_current_iban THEN
        IF EXISTS (
            SELECT 1 FROM account 
            WHERE iban = p_iban AND deleted_at IS NULL AND account_id != p_account_id
        ) THEN
            RAISE EXCEPTION 'Bu IBAN başka bir hesaba ait: %', p_iban;
        END IF;
    END IF;
    
    -- 5. STATUS DEĞİŞİKLİĞİ KONTROLÜ
    IF p_status IS NOT NULL AND p_status != p_current_status THEN
        
        -- Hesabın kartlarını kontrol et
        SELECT 
            COUNT(*) FILTER (WHERE status = 'ACTIVE') as active_count,
            COUNT(*) as total_count
        INTO p_active_cards_count, p_total_cards_count
        FROM card c
        JOIN card_type ct ON c.card_type_id = ct.card_type_id
        WHERE c.account_id = p_account_id 
          AND ct.type_name = 'ACCOUNT'
          AND c.deleted_at IS NULL;
        
        -- Hesabı pasifleştirirken aktif kartları kontrol et
        IF p_status IN ('INACTIVE', 'SUSPENDED') AND p_current_status = 'ACTIVE' THEN
            IF p_active_cards_count > 0 THEN
                RAISE EXCEPTION 'Bu hesapta % aktif kart bulunmaktadır. Hesabı pasifleştirmeden önce kartları pasifleştirin.', p_active_cards_count;
            END IF;
        END IF;
        
        -- Hesabı aktifleştirirken kart durumunu kontrol et
        IF p_status = 'ACTIVE' AND p_current_status IN ('INACTIVE', 'SUSPENDED') THEN
            IF p_total_cards_count > 0 THEN
                RAISE NOTICE 'Hesap aktifleştirildi ancak % adet kart pasif durumda. Gerekirse kartları manuel olarak aktifleştirin.', (p_total_cards_count - p_active_cards_count);
            END IF;
        END IF;
    END IF;
    
    -- 6. IBAN DEĞİŞİKLİĞİ RİSK KONTROLÜ
    IF p_iban IS NOT NULL AND p_iban != p_current_iban THEN
        -- Hesabın aktif kartları varsa IBAN değişikliği riskli
        IF p_active_cards_count > 0 THEN
            RAISE NOTICE 'DİKKAT: Bu hesabın % aktif kartı bulunmaktadır. IBAN değişikliği kartların çalışmasını etkileyebilir!', p_active_cards_count;
        END IF;
        
        RAISE NOTICE 'IBAN değiştirildi: % → %', p_current_iban, p_iban;
    END IF;
    
    -- 7. GÜNCELLEME İŞLEMİ
    UPDATE account
    SET 
        iban = COALESCE(p_iban, iban),
        account_name = COALESCE(p_account_name, account_name),
        status = COALESCE(p_status, status),
        updated_at = CURRENT_TIMESTAMP
    WHERE account_id = p_account_id;
    
    -- 8. BAŞARI MESAJI
    DECLARE
        updated_fields TEXT := '';
    BEGIN
        IF p_iban IS NOT NULL AND p_iban != p_current_iban THEN
            updated_fields := updated_fields || 'IBAN, ';
        END IF;
        IF p_account_name IS NOT NULL AND p_account_name != p_current_account_name THEN
            updated_fields := updated_fields || 'Ad, ';
        END IF;
        IF p_status IS NOT NULL AND p_status != p_current_status THEN
            updated_fields := updated_fields || 'Status, ';
        END IF;
        
        -- Son virgülü kaldır
        updated_fields := TRIM(TRAILING ', ' FROM updated_fields);
        
        IF updated_fields = '' THEN
            RAISE NOTICE 'Hesap bilgileri değiştirilmedi (ID: %)', p_account_id;
        ELSE
            RAISE NOTICE 'Hesap başarıyla güncellendi (ID: %) - Değişen alanlar: %', p_account_id, updated_fields;
        END IF;
    END;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Hesap güncelleme başarısız: %', SQLERRM;
END;
$$;