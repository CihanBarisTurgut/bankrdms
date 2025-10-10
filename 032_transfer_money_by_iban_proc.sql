CREATE OR REPLACE PROCEDURE transfer_money_by_iban(
    p_from_iban CHAR(26),
    p_to_iban CHAR(26),
    p_amount DECIMAL(13,3),
    p_description VARCHAR(100) DEFAULT 'IBAN para transferi'
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Kaynak hesap ve kart bilgileri
    p_from_account_id INT;
    p_from_account_deleted_at TIMESTAMP;
    p_from_account_status VARCHAR(20);
    p_from_customer_id INT;
    p_from_customer_deleted_at TIMESTAMP;
    p_from_card_id INT;
    p_from_card_deleted_at TIMESTAMP;
    p_from_card_status VARCHAR(20);
    p_from_balance DECIMAL(13,3);
    
    -- Hedef hesap ve kart bilgileri
    p_to_account_id INT;
    p_to_account_deleted_at TIMESTAMP;
    p_to_account_status VARCHAR(20);
    p_to_customer_id INT;
    p_to_customer_deleted_at TIMESTAMP;
    p_to_card_id INT;
    p_to_card_deleted_at TIMESTAMP;
    p_to_card_status VARCHAR(20);
    p_to_balance DECIMAL(13,3);
    
    -- Transaction type ve hesaplanan değerler
    p_transfer_type_id INT;
    p_from_new_balance DECIMAL(13,3);
    p_to_new_balance DECIMAL(13,3);
    
    -- Aktif kart sayısı kontrolü için
    p_from_active_card_count INT;
    p_to_active_card_count INT;
    
BEGIN
    -- 1. Input validasyonları
    IF p_from_iban IS NULL OR LENGTH(TRIM(p_from_iban)) != 26 THEN
        RAISE EXCEPTION 'Geçersiz gönderen IBAN formatı: %', p_from_iban;
    END IF;
    
    IF p_to_iban IS NULL OR LENGTH(TRIM(p_to_iban)) != 26 THEN
        RAISE EXCEPTION 'Geçersiz alıcı IBAN formatı: %', p_to_iban;
    END IF;
    
    IF p_from_iban = p_to_iban THEN
        RAISE EXCEPTION 'Gönderen ve alıcı IBAN aynı olamaz: %', p_from_iban;
    END IF;
    
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Transfer tutarı pozitif olmalıdır: %', p_amount;
    END IF;
    
    -- Maksimum transfer limiti (iş kuralı)
    IF p_amount > 1000000 THEN -- 1M TL limit
        RAISE EXCEPTION 'Tek seferde en fazla 1.000.000 TL transfer yapılabilir. İstenen: %', p_amount;
    END IF;
    
    -- 2. Transaction type kontrolü
    SELECT transaction_type_id INTO p_transfer_type_id 
    FROM transaction_type 
    WHERE type_name = 'TRANSFER';
    
    IF p_transfer_type_id IS NULL THEN
        RAISE EXCEPTION 'TRANSFER transaction type bulunamadı!';
    END IF;
    
    -- 3. Kaynak hesap bilgilerini al ve kontrol et
    SELECT account_id, deleted_at, status, customer_id 
    INTO p_from_account_id, p_from_account_deleted_at, p_from_account_status, p_from_customer_id
    FROM account 
    WHERE iban = p_from_iban;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Gönderen IBAN bulunamadı: %', p_from_iban;
    END IF;
    
    IF p_from_account_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Gönderen hesap silinmiş, transfer yapılamaz: %', p_from_iban;
    END IF;
    
    IF p_from_account_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Gönderen hesap aktif değil, transfer yapılamaz. Durum: %', p_from_account_status;
    END IF;
    
    -- 4. Hedef hesap bilgilerini al ve kontrol et
    SELECT account_id, deleted_at, status, customer_id 
    INTO p_to_account_id, p_to_account_deleted_at, p_to_account_status, p_to_customer_id
    FROM account 
    WHERE iban = p_to_iban;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Alıcı IBAN bulunamadı: %', p_to_iban;
    END IF;
    
    IF p_to_account_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Alıcı hesap silinmiş, transfer yapılamaz: %', p_to_iban;
    END IF;
    
    IF p_to_account_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Alıcı hesap aktif değil, transfer yapılamaz. Durum: %', p_to_account_status;
    END IF;
    
    -- 5. Müşteri kontrolleri
    -- Gönderen müşteri
    SELECT deleted_at INTO p_from_customer_deleted_at
    FROM customer
    WHERE customer_id = p_from_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Gönderen hesaba ait müşteri bulunamadı: %', p_from_customer_id;
    END IF;
    
    IF p_from_customer_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Gönderen müşteri silinmiş, transfer yapılamaz: %', p_from_customer_id;
    END IF;
    
    -- Alıcı müşteri
    SELECT deleted_at INTO p_to_customer_deleted_at
    FROM customer
    WHERE customer_id = p_to_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Alıcı hesaba ait müşteri bulunamadı: %', p_to_customer_id;
    END IF;
    
    IF p_to_customer_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Alıcı müşteri silinmiş, transfer yapılamaz: %', p_to_customer_id;
    END IF;
    
    -- 6. Aktif kart sayısı kontrolü (iş kuralı: her hesapta tek aktif ACCOUNT kart)
    SELECT COUNT(*) INTO p_from_active_card_count
    FROM card c
    JOIN card_type ct ON c.card_type_id = ct.card_type_id
    WHERE c.account_id = p_from_account_id 
      AND c.status = 'ACTIVE' 
      AND c.deleted_at IS NULL
      AND ct.type_name = 'ACCOUNT';
      
    SELECT COUNT(*) INTO p_to_active_card_count
    FROM card c
    JOIN card_type ct ON c.card_type_id = ct.card_type_id
    WHERE c.account_id = p_to_account_id 
      AND c.status = 'ACTIVE' 
      AND c.deleted_at IS NULL
      AND ct.type_name = 'ACCOUNT';
    
    IF p_from_active_card_count = 0 THEN
        RAISE EXCEPTION 'Gönderen hesaba bağlı aktif hesap kartı bulunamadı: %', p_from_iban;
    END IF;
    
    IF p_from_active_card_count > 1 THEN
        RAISE EXCEPTION 'Gönderen hesaba bağlı birden fazla aktif kart var. İş kuralı ihlali: %', p_from_iban;
    END IF;
    
    IF p_to_active_card_count = 0 THEN
        RAISE EXCEPTION 'Alıcı hesaba bağlı aktif hesap kartı bulunamadı: %', p_to_iban;
    END IF;
    
    IF p_to_active_card_count > 1 THEN
        RAISE EXCEPTION 'Alıcı hesaba bağlı birden fazla aktif kart var. İş kuralı ihlali: %', p_to_iban;
    END IF;
    
    -- 7. Gönderen kart bilgilerini al
    SELECT c.card_id, c.deleted_at, c.status, c.balance
    INTO p_from_card_id, p_from_card_deleted_at, p_from_card_status, p_from_balance
    FROM card c
    JOIN card_type ct ON c.card_type_id = ct.card_type_id
    WHERE c.account_id = p_from_account_id
      AND c.status = 'ACTIVE'
      AND c.deleted_at IS NULL
      AND ct.type_name = 'ACCOUNT';
    
    -- 8. Alıcı kart bilgilerini al
    SELECT c.card_id, c.deleted_at, c.status, c.balance
    INTO p_to_card_id, p_to_card_deleted_at, p_to_card_status, p_to_balance
    FROM card c
    JOIN card_type ct ON c.card_type_id = ct.card_type_id
    WHERE c.account_id = p_to_account_id
      AND c.status = 'ACTIVE'
      AND c.deleted_at IS NULL
      AND ct.type_name = 'ACCOUNT';
    
    -- 9. Bakiye kontrolü
    IF p_from_balance < p_amount THEN
        RAISE EXCEPTION 'Yetersiz bakiye. Mevcut bakiye: %, İstenen transfer: %', p_from_balance, p_amount;
    END IF;
    
    -- 10. Maksimum alıcı bakiye kontrolü (isteğe bağlı iş kuralı)
    p_to_new_balance := p_to_balance + p_amount;
    IF p_to_new_balance > 10000000 THEN -- 10M TL limit
        RAISE EXCEPTION 'Alıcı hesap maksimum bakiye limitini (10.000.000 TL) aşacak. Mevcut: %, Transfer: %, Toplam: %', 
                        p_to_balance, p_amount, p_to_new_balance;
    END IF;
    
    -- 11. Hesaplamaları yap
    p_from_new_balance := p_from_balance - p_amount;
    
    -- 12. Transfer işlemlerini gerçekleştir
    -- Gönderen karttan para düş
    UPDATE card 
    SET balance = balance - p_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE card_id = p_from_card_id;
    
    -- Alıcı karta para ekle
    UPDATE card 
    SET balance = balance + p_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE card_id = p_to_card_id;
    
    -- 13. Transaction kayıtlarını ekle
    -- Gönderen için (çıkış)
    INSERT INTO transaction (card_id, transaction_type_id, description, amount)
    VALUES (p_from_card_id, p_transfer_type_id, 
            CONCAT(p_description, ' - Gönderilen (Alıcı: ', p_to_iban, ')'), 
            p_amount);
    
    -- Alıcı için (giriş)
    INSERT INTO transaction (card_id, transaction_type_id, description, amount)
    VALUES (p_to_card_id, p_transfer_type_id, 
            CONCAT(p_description, ' - Gelen (Gönderen: ', p_from_iban, ')'), 
            p_amount);
    
    -- 14. Başarı mesajı
    RAISE NOTICE 'Transfer başarılı! Gönderen IBAN: %, Alıcı IBAN: %, Tutar: %, Gönderen yeni bakiye: %, Alıcı yeni bakiye: %', 
                 p_from_iban, p_to_iban, p_amount, p_from_new_balance, p_to_new_balance;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Hata durumunda rollback otomatik olacak
        RAISE EXCEPTION 'Transfer işlemi başarısız: %', SQLERRM;
END;
$$;