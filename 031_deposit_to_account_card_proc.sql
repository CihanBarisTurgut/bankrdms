CREATE OR REPLACE PROCEDURE deposit_to_account_card(
    p_card_id INT,
    p_amount DECIMAL(13,3),
    p_description VARCHAR(100) DEFAULT 'Hesaba para yatırıldı'
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Kart bilgileri
    p_card_deleted_at TIMESTAMP;
    p_card_status VARCHAR(20);
    p_card_type_name VARCHAR(50);
    p_account_id INT;
    p_customer_id INT;
    p_current_balance DECIMAL(13,3);
    
    -- Hesap ve müşteri bilgileri
    p_account_deleted_at TIMESTAMP;
    p_account_status VARCHAR(20);
    p_customer_deleted_at TIMESTAMP;
    
    -- Transaction type
    p_deposit_type_id INT;
    
    -- Hesaplanan değerler
    p_new_balance DECIMAL(13,3);
    
BEGIN
    -- 1. Input validasyonları
    IF p_card_id IS NULL OR p_card_id <= 0 THEN
        RAISE EXCEPTION 'Geçersiz kart ID: %', p_card_id;
    END IF;
    
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Yatırılacak tutar pozitif olmalıdır: %', p_amount;
    END IF;
    
    -- Maksimum yatırma limiti kontrolü (isteğe bağlı iş kuralı)
    IF p_amount > 1000000 THEN -- 1 milyon TL limit
        RAISE EXCEPTION 'Tek seferde en fazla 1.000.000 TL yatırılabilir. İstenen: %', p_amount;
    END IF;
    
    -- 2. Transaction type kontrolü
    SELECT transaction_type_id INTO p_deposit_type_id
    FROM transaction_type 
    WHERE type_name = 'DEPOSIT';
    
    IF p_deposit_type_id IS NULL THEN
        RAISE EXCEPTION 'DEPOSIT transaction type bulunamadı!';
    END IF;
    
    -- 3. Kart bilgilerini tek sorguda al (performans için)
    SELECT c.deleted_at, c.status, c.account_id, c.customer_id, c.balance, ct.type_name
    INTO p_card_deleted_at, p_card_status, p_account_id, p_customer_id, p_current_balance, p_card_type_name
    FROM card c
    JOIN card_type ct ON c.card_type_id = ct.card_type_id
    WHERE c.card_id = p_card_id;
    
    -- Kart varlık kontrolü
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kart bulunamadı (ID: %)', p_card_id;
    END IF;
    
    -- Kart silinme kontrolü
    IF p_card_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Silinmiş bir karta para yatırılamaz (ID: %)', p_card_id;
    END IF;
    
    -- Kart aktiflik kontrolü
    IF p_card_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Sadece aktif kartlara para yatırılabilir. Kart durumu: % (ID: %)', p_card_status, p_card_id;
    END IF;
    
    -- Kart tipi kontrolü
    IF p_card_type_name != 'ACCOUNT' THEN
        RAISE EXCEPTION 'Para yatırma işlemi sadece hesap kartları için geçerlidir. Kart tipi: % (ID: %)', p_card_type_name, p_card_id;
    END IF;
    
    -- Account ID kontrolü (ACCOUNT kartlarda olması gerekir)
    IF p_account_id IS NULL THEN
        RAISE EXCEPTION 'Hesap kartında account_id bulunamadı (ID: %)', p_card_id;
    END IF;
    
    -- 4. Hesap kontrolü
    SELECT deleted_at, status INTO p_account_deleted_at, p_account_status
    FROM account
    WHERE account_id = p_account_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Karta bağlı hesap bulunamadı (Account ID: %)', p_account_id;
    END IF;
    
    IF p_account_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Karta bağlı hesap silinmiş, para yatırılamaz (Account ID: %)', p_account_id;
    END IF;
    
    IF p_account_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Karta bağlı hesap aktif değil, para yatırılamaz. Hesap durumu: % (ID: %)', p_account_status, p_account_id;
    END IF;
    
    -- 5. Müşteri kontrolü
    SELECT deleted_at INTO p_customer_deleted_at
    FROM customer
    WHERE customer_id = p_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Karta ait müşteri bulunamadı (Customer ID: %)', p_customer_id;
    END IF;
    
    IF p_customer_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Karta ait müşteri silinmiş, para yatırılamaz (Customer ID: %)', p_customer_id;
    END IF;
    
    -- 6. Maksimum bakiye limiti kontrolü (isteğe bağlı iş kuralı)
    p_new_balance := p_current_balance + p_amount;
    IF p_new_balance > 10000000 THEN -- 10 milyon TL maksimum bakiye
        RAISE EXCEPTION 'Maksimum bakiye limiti (10.000.000 TL) aşılacak. Mevcut: %, Yatırılacak: %, Toplam: %', 
                        p_current_balance, p_amount, p_new_balance;
    END IF;
    
    -- 7. Database işlemlerini gerçekleştir
    -- Bakiyeyi güncelle
    UPDATE card
    SET balance = balance + p_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE card_id = p_card_id;
    
    -- Transaction kaydı ekle
    INSERT INTO transaction (card_id, transaction_type_id, description, amount)
    VALUES (p_card_id, p_deposit_type_id, p_description, p_amount);
    
    -- 8. Başarı mesajı
    RAISE NOTICE 'Para yatırma başarılı! Kart ID: %, Yatırılan: %, Önceki bakiye: %, Yeni bakiye: %', 
                 p_card_id, p_amount, p_current_balance, p_new_balance;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Hata durumunda rollback otomatik olacak
        RAISE EXCEPTION 'Para yatırma işlemi başarısız: %', SQLERRM;
END;
$$;