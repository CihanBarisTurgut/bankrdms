CREATE OR REPLACE PROCEDURE expense_money_by_card(
    p_card_id INT,
    p_expense_amount DECIMAL,
    p_expense_description VARCHAR(100)
)
LANGUAGE plpgsql
AS $$ 
DECLARE
    p_card_deleted_at TIMESTAMP;
    p_account_deleted_at TIMESTAMP;
    p_customer_deleted_at TIMESTAMP;
    p_card_status VARCHAR(20);
    p_account_id INT;
    p_balance DECIMAL;
    p_limit DECIMAL;
    p_customer_id INT;
    p_current_debt DECIMAL;
    p_expense_type_id INT;
BEGIN
    
    -- EXPENSE transaction type ID'sini al
    SELECT transaction_type_id INTO p_expense_type_id
    FROM transaction_type
    WHERE type_name = 'EXPENSE';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'EXPENSE transaction type bulunamadı!';
    END IF;
    
    -- 1. Kart temel bilgilerini al
    SELECT customer_id, account_id, deleted_at, status INTO p_customer_id, p_account_id, p_card_deleted_at, p_card_status
    FROM card
    WHERE card_id = p_card_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Böyle bir kart bulunmamaktadır, harcama yapamazsınız: %', p_card_id;
    END IF;
    
    -- 2. Kart silinmiş mi kontrolü
    IF p_card_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Bu kart silinmiştir, harcama yapamazsınız: %', p_card_id;
    END IF;
    
    -- 3. Kart aktif mi kontrolü
    IF p_card_status != 'ACTIVE' THEN
        RAISE EXCEPTION 'Bu kart aktif değildir, harcama yapamazsınız. Kart durumu: %', p_card_status;
    END IF;
    
    -- 4. Müşteri kontrolü
    SELECT deleted_at INTO p_customer_deleted_at
    FROM customer
    WHERE customer_id = p_customer_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Böyle bir müşteri yok, harcama yapamazsınız: %', p_customer_id;
    ELSIF p_customer_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Müşteri kaydı silinmiş, harcama yapamazsınız: %', p_customer_id;
    END IF;
    
    -- 5. Harcama tutarı pozitif mi kontrolü
    IF p_expense_amount <= 0 THEN
        RAISE EXCEPTION 'Harcama tutarı pozitif olmalıdır: %', p_expense_amount;
    END IF;
    
    -- 6. Hesap kartı mı kredi kartı mı kontrol et
    IF p_account_id IS NOT NULL THEN
        -- HESAP KARTI İŞLEMLERİ
        
        -- Hesap kontrolü
        SELECT deleted_at INTO p_account_deleted_at
        FROM account
        WHERE account_id = p_account_id;
        
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Bu hesap kartına ait hesap yoktur, harcama yapamazsınız: %', p_card_id;
        ELSIF p_account_deleted_at IS NOT NULL THEN
            RAISE EXCEPTION 'Bu hesap kartına ait hesap silinmiştir, harcama yapamazsınız: %', p_card_id;
        END IF;
        
        -- Bakiye kontrolü
        SELECT balance INTO p_balance
        FROM card
        WHERE card_id = p_card_id;
        
        IF p_balance < p_expense_amount THEN
            RAISE EXCEPTION 'Bu harcama için hesap bakiyeniz yetersizdir. Mevcut bakiye: %, İstenen: %', p_balance, p_expense_amount;
        END IF;
        
        -- Hesap kartından harcama yap
        UPDATE card
        SET balance = balance - p_expense_amount
        WHERE card_id = p_card_id;
        
        -- Transaction kaydı ekle
        INSERT INTO transaction (card_id, transaction_type_id, description, amount)
        VALUES (p_card_id, p_expense_type_id, p_expense_description, p_expense_amount);
        
        RAISE NOTICE 'Hesap kartından harcama yapılmıştır: %, Kalan bakiye: %', p_expense_amount, (p_balance - p_expense_amount);
        
    ELSE 
        -- KREDİ KARTI İŞLEMLERİ
        
        -- Limit ve borç bilgilerini al
        SELECT limit_amount, current_debt INTO p_limit, p_current_debt
        FROM card
        WHERE card_id = p_card_id;
        
        -- Limit kontrolü
        IF p_limit < (p_expense_amount + p_current_debt) THEN
            RAISE EXCEPTION 'Bu harcama için kart limitiniz yetersizdir. Kalan limit: %, İstenen: %', (p_limit - p_current_debt), p_expense_amount;
        END IF;
        
        -- Kredi kartından harcama yap
        UPDATE card
        SET current_debt = current_debt + p_expense_amount
        WHERE card_id = p_card_id;
        
        -- Transaction kaydı ekle
        INSERT INTO transaction (card_id, transaction_type_id, description, amount)
        VALUES (p_card_id, p_expense_type_id, p_expense_description, p_expense_amount);
        
        RAISE NOTICE 'Kredi kartından harcama yapılmıştır: %, Toplam borç: %', p_expense_amount, (p_current_debt + p_expense_amount);
        
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Hata durumunda tüm değişiklikleri geri al
        RAISE EXCEPTION 'Harcama işlemi başarısız: %', SQLERRM;
END;
$$;