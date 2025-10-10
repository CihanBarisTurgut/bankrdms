CREATE OR REPLACE PROCEDURE payment_to_credit_card(
    p_source_iban CHAR(26),           -- Ödeme yapılacak hesabın IBAN'ı
    p_credit_card_id INT,             -- Borcu ödenecek kredi kartının ID'si
    p_payment_amount DECIMAL(13,3),   -- Ödenecek tutar
    p_description VARCHAR(100) DEFAULT 'Kredi kartı borç ödemesi'
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Kaynak hesap ve kart bilgileri
    p_source_account_id INT;
    p_source_account_deleted_at TIMESTAMP;
    p_source_account_status VARCHAR(20);
    p_source_card_id INT;
    p_source_card_deleted_at TIMESTAMP;
    p_source_card_status VARCHAR(20);
    p_source_card_type_name VARCHAR(50);
    p_source_balance DECIMAL(13,3);
    p_source_customer_id INT;
    p_source_customer_deleted_at TIMESTAMP;
    
    -- Hedef kredi kartı bilgileri
    p_credit_card_deleted_at TIMESTAMP;
    p_credit_card_status VARCHAR(20);
    p_credit_card_type_name VARCHAR(50);
    p_credit_current_debt DECIMAL(13,3);
    p_credit_limit DECIMAL(13,3);
    p_credit_customer_id INT;
    p_credit_customer_deleted_at TIMESTAMP;
    
    -- Transaction type ID'leri
    p_payment_type_id INT;
    p_withdrawal_type_id INT;
    
    -- Hesaplanan değerler
    p_actual_payment_amount DECIMAL(13,3);
    p_remaining_debt DECIMAL(13,3);
    p_remaining_balance DECIMAL(13,3);
    
BEGIN
    -- 1. Input validasyonları

    
    IF p_credit_card_id IS NULL OR p_credit_card_id <= 0 THEN
        RAISE EXCEPTION 'Geçersiz kredi kartı ID: %', p_credit_card_id;
    END IF;
    
    IF p_payment_amount IS NULL OR p_payment_amount <= 0 THEN
        RAISE EXCEPTION 'Ödeme tutarı pozitif olmalıdır: %', p_payment_amount;
    END IF;
    
    -- 2. Transaction type ID'lerini al
    SELECT transaction_type_id INTO p_payment_type_id
    FROM transaction_type WHERE type_name = 'PAYMENT';
    
    SELECT transaction_type_id INTO p_withdrawal_type_id
    FROM transaction_type WHERE type_name = 'WITHDRAWAL';
    
    IF p_payment_type_id IS NULL THEN
        RAISE EXCEPTION 'PAYMENT transaction type bulunamadı!';
    END IF;
    
    IF p_withdrawal_type_id IS NULL THEN
        RAISE EXCEPTION 'WITHDRAWAL transaction type bulunamadı!';
    END IF;
    
    -- 3. Kaynak hesap bilgilerini al
    SELECT account_id, status, deleted_at, customer_id 
    INTO p_source_account_id, p_source_account_status, p_source_account_deleted_at, p_source_customer_id
    FROM account
    WHERE iban = p_source_iban;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bu IBAN ile hesap bulunamadı: %', p_source_iban;
    END IF;
    
    IF p_source_account_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Kaynak hesap silinmiş, ödeme yapılamaz: %', p_source_iban;
    END IF;
    
    IF p_source_account_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Kaynak hesap aktif değil, ödeme yapılamaz. Durum: %', p_source_account_status;
    END IF;
    
    -- 4. Kaynak müşteri kontrolü
    SELECT deleted_at INTO p_source_customer_deleted_at
    FROM customer
    WHERE customer_id = p_source_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kaynak hesaba ait müşteri bulunamadı: %', p_source_customer_id;
    END IF;
    
    IF p_source_customer_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Kaynak hesap müşterisi silinmiş, ödeme yapılamaz: %', p_source_customer_id;
    END IF;
    
    -- 5. Bu hesaba bağlı aktif ACCOUNT kartını bul
    SELECT c.card_id, c.status, c.deleted_at, c.balance, ct.type_name
    INTO p_source_card_id, p_source_card_status, p_source_card_deleted_at, p_source_balance, p_source_card_type_name
    FROM card c
    JOIN card_type ct ON c.card_type_id = ct.card_type_id
    WHERE c.account_id = p_source_account_id 
      AND c.status = 'ACTIVE' 
      AND c.deleted_at IS NULL
      AND ct.type_name = 'ACCOUNT';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bu IBAN''a bağlı aktif hesap kartı bulunamadı: %', p_source_iban;
    END IF;
    
    -- 6. Birden fazla aktif kart kontrolü (iş kuralı)
    IF (SELECT COUNT(*) FROM card c
        JOIN card_type ct ON c.card_type_id = ct.card_type_id
        WHERE c.account_id = p_source_account_id 
          AND c.status = 'ACTIVE' 
          AND c.deleted_at IS NULL
          AND ct.type_name = 'ACCOUNT') > 1 THEN
        RAISE EXCEPTION 'Bu IBAN''a bağlı birden fazla aktif hesap kartı var. İş kuralı ihlali: %', p_source_iban;
    END IF;
    
    -- 7. Hedef kredi kartı bilgilerini al
    SELECT c.deleted_at, c.status, c.current_debt, c.limit_amount, c.customer_id, ct.type_name
    INTO p_credit_card_deleted_at, p_credit_card_status, p_credit_current_debt, p_credit_limit, p_credit_customer_id, p_credit_card_type_name
    FROM card c
    JOIN card_type ct ON c.card_type_id = ct.card_type_id
    WHERE c.card_id = p_credit_card_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Hedef kredi kartı bulunamadı: %', p_credit_card_id;
    END IF;
    
    IF p_credit_card_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Hedef kredi kartı silinmiş, ödeme yapılamaz: %', p_credit_card_id;
    END IF;
    
    IF p_credit_card_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Hedef kredi kartı aktif değil, ödeme yapılamaz. Durum: %', p_credit_card_status;
    END IF;
    
    IF p_credit_card_type_name != 'CREDIT' THEN
        RAISE EXCEPTION 'Hedef kart kredi kartı değil: % (Tip: %)', p_credit_card_id, p_credit_card_type_name;
    END IF;
    
    -- 8. Hedef müşteri kontrolü
    SELECT deleted_at INTO p_credit_customer_deleted_at
    FROM customer
    WHERE customer_id = p_credit_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Hedef kredi kartı müşterisi bulunamadı: %', p_credit_customer_id;
    END IF;
    
    IF p_credit_customer_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Hedef kredi kartı müşterisi silinmiş, ödeme yapılamaz: %', p_credit_customer_id;
    END IF;
    
    -- 9. Müşteri eşleştirme kontrolü (GÜVENLİK)
    -- Kaynak hesap ve hedef kredi kartı aynı müşteriye ait olmalı
    IF p_source_customer_id != p_credit_customer_id THEN
        RAISE EXCEPTION 'Güvenlik ihlali: Kaynak hesap müşterisi (%) ile hedef kredi kartı müşterisi (%) farklı. Başka müşterinin hesabından ödeme yapılamaz!', 
                        p_source_customer_id, p_credit_customer_id;
    END IF;
    
    -- 10. İş mantığı kontrolleri
    -- Kredi kartında borç var mı?
    IF p_credit_current_debt IS NULL OR p_credit_current_debt <= 0 THEN
        RAISE EXCEPTION 'Bu kredi kartında ödenecek borç yok. Mevcut borç: %', COALESCE(p_credit_current_debt, 0);
    END IF;
    
    -- Kaynak hesapta yeterli bakiye var mı?
    IF p_source_balance < p_payment_amount THEN
        RAISE EXCEPTION 'Yetersiz bakiye. Mevcut bakiye: %, İstenen tutar: %', p_source_balance, p_payment_amount;
    END IF;
    
    -- Ödeme tutarı mevcut borçtan fazla mı? (fazla ödeme kontrolü)
    IF p_payment_amount > p_credit_current_debt THEN
        -- İki seçenek: 1) Sadece borç kadar öde  2) Hata ver
        -- Seçenek 1: Otomatik düzeltme (kullanıcı dostu)
        p_actual_payment_amount := p_credit_current_debt;
        RAISE NOTICE 'Ödeme tutarı (%) mevcut borçtan (%) fazla. Sadece borç kadar (%) ödenecek.', 
                     p_payment_amount, p_credit_current_debt, p_actual_payment_amount;
        
        -- Seçenek 2: Hata verme (daha katı kontrol)
        -- RAISE EXCEPTION 'Ödeme tutarı (%) mevcut borçtan (%) fazla olamaz!', p_payment_amount, p_credit_current_debt;
    ELSE
        p_actual_payment_amount := p_payment_amount;
    END IF;
    
    -- Ödeme tutarı kart limitinden fazla olamaz (iş kuralı)
    IF p_actual_payment_amount > p_credit_limit THEN
        RAISE EXCEPTION 'Tek seferde yapılabilecek ödeme kart limitini (%) aşamaz. İstenen ödeme: %', 
                        p_credit_limit, p_actual_payment_amount;
    END IF;
    
    -- 11. Hesaplamaları yap
    p_remaining_debt := p_credit_current_debt - p_actual_payment_amount;
    p_remaining_balance := p_source_balance - p_actual_payment_amount;
    
    -- 12. Database işlemlerini gerçekleştir
    -- Kaynak hesap kartından parayı düş
    UPDATE card
    SET balance = balance - p_actual_payment_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE card_id = p_source_card_id;
    
    -- Kredi kartı borcunu azalt
    UPDATE card
    SET current_debt = current_debt - p_actual_payment_amount,
        updated_at = CURRENT_TIMESTAMP
    WHERE card_id = p_credit_card_id;
    
    -- 13. Transaction kayıtlarını ekle
    -- Kaynak karttan para çekme kaydı
    INSERT INTO transaction (card_id, transaction_type_id, description, amount)
    VALUES (p_source_card_id, p_withdrawal_type_id, 
            p_description, 
            p_actual_payment_amount);
    
    -- Hedef karta borç ödeme kaydı
    INSERT INTO transaction (card_id, transaction_type_id, description, amount)
    VALUES (p_credit_card_id, p_payment_type_id, 
            CONCAT(p_description, ' - Borç ödemesi (Kaynak IBAN: ', p_source_iban, ')'), 
            p_actual_payment_amount);
    
    -- 14. Başarı mesajı
    RAISE NOTICE 'Borç ödeme başarılı! Ödenen: %, Kalan borç: %, Kalan bakiye: %', 
                 p_actual_payment_amount, p_remaining_debt, p_remaining_balance;
    
    IF p_remaining_debt = 0 THEN
        RAISE NOTICE 'Tebrikler! Kredi kartı borcu tamamen ödendi.';
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Hata durumunda rollback otomatik olacak
        RAISE EXCEPTION 'Borç ödeme işlemi başarısız: %', SQLERRM;
END;
$$;