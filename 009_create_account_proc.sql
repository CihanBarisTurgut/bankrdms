CREATE OR REPLACE PROCEDURE create_account_proc(
    p_customer_id INT,
    p_iban VARCHAR,
    p_account_name VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    p_customer_deleted_at TIMESTAMP;
    p_account_deleted_at TIMESTAMP;
BEGIN

	-- 1. INPUT VALIDASYONU
    IF p_customer_id IS NULL OR p_customer_id <= 0 THEN
        RAISE EXCEPTION 'Geçersiz müşteri ID: %', p_customer_id;
    END IF;
    
    IF p_iban IS NULL OR LENGTH(TRIM(p_iban)) = 0 THEN
        RAISE EXCEPTION 'IBAN boş olamaz';
    END IF;
    
    IF p_account_name IS NULL OR LENGTH(TRIM(p_account_name)) = 0 THEN
        RAISE EXCEPTION 'Hesap adı boş olamaz';
    END IF;

	
    -- Müşterinin varlığını ve silinme durumunu kontrol et
    SELECT deleted_at INTO p_customer_deleted_at
    FROM customer
    WHERE customer_id = p_customer_id;

    -- Müşteri bulunamazsa hata 
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Müşteri bulunamadı (ID: %)', p_customer_id;
    END IF;

    -- Müşteri silinmişse hata 
    IF p_customer_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Silinmiş bir müşteriye hesap oluşturulamaz (ID: %)', p_customer_id;
    END IF;

    -- IBAN'ın varlığını ve silinme durumunu kontrol et
    SELECT deleted_at INTO p_account_deleted_at
    FROM account
    WHERE iban = p_iban;

    -- IBAN zaten mevcut ve silinmemişse hata 
    IF FOUND AND p_account_deleted_at IS NULL THEN
        RAISE EXCEPTION 'Bu IBAN zaten aktif bir hesaba ait (IBAN: %)', p_iban;
    END IF;

    -- IBAN mevcut ve silinmişse, hesabı güncelle
    IF FOUND AND p_account_deleted_at IS NOT NULL THEN
        UPDATE account
        SET 
            customer_id = p_customer_id,
            account_name = p_account_name,
            deleted_at = NULL
        WHERE iban = p_iban;
        
        RAISE NOTICE 'Daha önce silinmiş hesap yeniden etkinleştirildi (IBAN: %)', p_iban;
    
    -- IBAN mevcut değilse, yeni bir hesap ekle
    ELSE
        INSERT INTO account(customer_id, iban, account_name)
        VALUES(p_customer_id, p_iban, p_account_name);
        
        RAISE NOTICE 'Yeni hesap başarıyla oluşturuldu (IBAN: %)', p_iban;
    END IF;

END;
$$;
