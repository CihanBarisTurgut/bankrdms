CREATE OR REPLACE PROCEDURE withdraw_from_account_card(
    p_card_id INT,
    p_amount DECIMAL(13,3),
    p_description VARCHAR(100) DEFAULT 'Hesabınızdan para çekildi'
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Kart bilgileri
    p_card_deleted_at TIMESTAMP;
    p_card_status VARCHAR(20);
    p_card_type_name VARCHAR(50);
    p_current_balance DECIMAL(13,3);
    
    -- Hesap bilgileri
    p_account_id INT;
    p_account_deleted_at TIMESTAMP;
    p_account_status VARCHAR(20);
    
    -- Müşteri bilgileri
    p_customer_id INT;
    p_customer_deleted_at TIMESTAMP;
    
    -- Transaction type
    p_withdrawal_type_id INT;
    
    -- Limitler
    p_min_withdrawal DECIMAL(13,3) := 1.00;
    p_max_withdrawal DECIMAL(13,3) := 50000.00; -- Günlük çekim limiti
    p_min_balance DECIMAL(13,3) := 0.00; -- Minimum bakiye
BEGIN
    -- 1. INPUT VALİDASYONU
    IF p_card_id IS NULL OR p_card_id <= 0 THEN
        RAISE EXCEPTION 'Geçersiz kart ID: %', p_card_id;
    END IF;
    
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Çekim tutarı pozitif olmalıdır: %', p_amount;
    END IF;
    
    IF p_amount < p_min_withdrawal THEN
        RAISE EXCEPTION 'Minimum çekim tutarı % TL''dir', p_min_withdrawal;
    END IF;
    
    IF p_amount > p_max_withdrawal THEN
        RAISE EXCEPTION 'Maksimum çekim tutarı % TL''dir', p_max_withdrawal;
    END IF;
    
    -- 2. TRANSACTION TYPE KONTROLÜ
    SELECT transaction_type_id INTO p_withdrawal_type_id 
    FROM transaction_type 
    WHERE type_name = 'WITHDRAWAL';
    
    IF p_withdrawal_type_id IS NULL THEN
        RAISE EXCEPTION 'WITHDRAWAL transaction type bulunamadı!';
    END IF;
    
    -- 3. KART BİLGİLERİNİ TEK SORGUDA AL (Performance)
    SELECT 
        c.deleted_at,
        c.status,
        ct.type_name,
        c.balance,
        c.account_id,
        c.customer_id
    INTO 
        p_card_deleted_at,
        p_card_status,
        p_card_type_name,
        p_current_balance,
        p_account_id,
        p_customer_id
    FROM card c
    JOIN card_type ct ON c.card_type_id = ct.card_type_id
    WHERE c.card_id = p_card_id;
    
    -- 4. KART KONTROL
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kart bulunamadı (ID: %)', p_card_id;
    END IF;
    
    IF p_card_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Silinmiş bir karttan para çekilemez (ID: %)', p_card_id;
    END IF;
    
    IF p_card_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Sadece aktif kartlardan para çekilebilir. Kart durumu: %', p_card_status;
    END IF;
    
    IF p_card_type_name != 'ACCOUNT' THEN
        RAISE EXCEPTION 'Para çekme işlemi sadece hesap kartları için geçerlidir. Kart tipi: %', p_card_type_name;
    END IF;
    
    -- 5. BAKİYE KONTROL
    IF p_current_balance IS NULL THEN
        RAISE EXCEPTION 'Kart bakiye bilgisi bulunamadı';
    END IF;
    
    IF p_current_balance < p_amount THEN
        RAISE EXCEPTION 'Yetersiz bakiye! Mevcut bakiye: % TL, Çekilmek istenen: % TL', 
                        p_current_balance, p_amount;
    END IF;
    
    IF (p_current_balance - p_amount) < p_min_balance THEN
        RAISE EXCEPTION 'İşlem sonrası bakiye minimum bakiyenin (% TL) altına düşemez!', p_min_balance;
    END IF;
    
    -- 6. HESAP KONTROL
    SELECT deleted_at, status INTO p_account_deleted_at, p_account_status
    FROM account
    WHERE account_id = p_account_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Karta bağlı hesap bulunamadı (Account ID: %)', p_account_id;
    END IF;
    
    IF p_account_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Karta bağlı hesap silinmiş, işlem yapılamaz (Account ID: %)', p_account_id;
    END IF;
    
    IF p_account_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Karta bağlı hesap aktif değil. Hesap durumu: %', p_account_status;
    END IF;
    
    -- 7. MÜŞTERİ KONTROL
    SELECT deleted_at INTO p_customer_deleted_at
    FROM customer
    WHERE customer_id = p_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Müşteri bulunamadı (Customer ID: %)', p_customer_id;
    END IF;
    
    IF p_customer_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Silinmiş müşteriye ait karttan işlem yapılamaz (Customer ID: %)', p_customer_id;
    END IF;
    
    -- 8. İŞLEMİ GERÇEKLEŞTİR
    -- Önce transaction kaydı
    INSERT INTO transaction(card_id, transaction_type_id, description, amount)
    VALUES(p_card_id, p_withdrawal_type_id, p_description, p_amount);
    
    -- Sonra bakiye güncellemesi
    UPDATE card
    SET balance = balance - p_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE card_id = p_card_id;
    
    -- Başarı mesajı
    RAISE NOTICE 'Para çekme işlemi başarılı! Kart ID: %, Çekilen: % TL, Kalan Bakiye: % TL', 
                 p_card_id, p_amount, (p_current_balance - p_amount);
    
EXCEPTION
    WHEN OTHERS THEN
        -- Hata durumunda rollback otomatik olur
        RAISE EXCEPTION 'Para çekme işlemi başarısız: %', SQLERRM;
END;
$$;