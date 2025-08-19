CREATE OR REPLACE PROCEDURE init_setup()
LANGUAGE plpgsql
AS $$
DECLARE
    p_customer_id INT;
    p_account_id INT;
    card_type_account_id INT;
    card_type_credit_id INT;
    card_id_account_89 INT;
    card_id_credit_88 INT;
    card_id_credit_87 INT;
    card_id_account_90 INT;
    transaction_type_deposit_id INT;
    transaction_type_withdrawal_id INT;
    transaction_type_expense_id INT;
    transaction_type_transfer_id INT;
    transaction_type_payment_id INT;
BEGIN
    -- Lookup
    INSERT INTO card_type(type_name, description) VALUES ('ACCOUNT','ACCOUNT_CARD') ON CONFLICT (type_name) DO NOTHING;
    INSERT INTO card_type(type_name, description) VALUES ('CREDIT','CREDIT_CARD') ON CONFLICT (type_name) DO NOTHING;
    -- Yatırma, çekme, harcama, ödeme, transfer
    INSERT INTO transaction_type(type_name) VALUES('DEPOSIT') ON CONFLICT (type_name) DO NOTHING;
    INSERT INTO transaction_type(type_name) VALUES('WITHDRAWAL') ON CONFLICT (type_name) DO NOTHING;
    INSERT INTO transaction_type(type_name) VALUES('EXPENSE') ON CONFLICT (type_name) DO NOTHING;
    INSERT INTO transaction_type(type_name) VALUES('PAYMENT') ON CONFLICT (type_name) DO NOTHING;
    INSERT INTO transaction_type(type_name) VALUES('TRANSFER') ON CONFLICT (type_name) DO NOTHING;

    -- Lookup ID'lerini al
    SELECT card_type_id INTO card_type_account_id FROM card_type WHERE type_name = 'ACCOUNT';
    SELECT card_type_id INTO card_type_credit_id FROM card_type WHERE type_name = 'CREDIT';
    SELECT transaction_type_id INTO transaction_type_deposit_id FROM transaction_type WHERE type_name = 'DEPOSIT';
    SELECT transaction_type_id INTO transaction_type_withdrawal_id FROM transaction_type WHERE type_name = 'WITHDRAWAL';
    SELECT transaction_type_id INTO transaction_type_expense_id FROM transaction_type WHERE type_name = 'EXPENSE';
    SELECT transaction_type_id INTO transaction_type_payment_id FROM transaction_type WHERE type_name = 'PAYMENT';
    SELECT transaction_type_id INTO transaction_type_transfer_id FROM transaction_type WHERE type_name = 'TRANSFER';

    -- 1. adım
    INSERT INTO customer(customer_name, tc_no, birth_date, birth_place)
    VALUES('Gün Gören', '11111111111', '1993-02-01', 'Eskişehir')
    RETURNING customer_id INTO p_customer_id;

    -- 1. adım
    INSERT INTO account(customer_id, iban, account_name)
    VALUES(p_customer_id, 'TR011234154645788999', 'Vadesiz Anadolu')
    RETURNING account_id INTO p_account_id;

    -- 2. adım
    INSERT INTO card(customer_id, account_id, card_type_id, card_number, expiry_month, expiry_year, ccv)
    VALUES(p_customer_id, p_account_id, card_type_account_id, '1234987654645489', 12, 2028, '123')
    RETURNING card_id INTO card_id_account_89;

    -- 3. adım
    INSERT INTO card(customer_id, card_type_id, card_number, expiry_month, expiry_year, ccv, limit_amount, current_debt)
    VALUES(p_customer_id, card_type_credit_id, '1234879654645488', 12, 2028, '456', 5000.00, 0.00)
    RETURNING card_id INTO card_id_credit_88;

    INSERT INTO card(customer_id, card_type_id, card_number, expiry_month, expiry_year, ccv, limit_amount, current_debt)
    VALUES(p_customer_id, card_type_credit_id, '1234879654645487', 12, 2028, '789', 3000.00, 0.00)
    RETURNING card_id INTO card_id_credit_87;

    -- 4. adım
    INSERT INTO transaction(card_id, transaction_type_id, description, amount)
    VALUES(card_id_credit_88, transaction_type_expense_id, 'Yaz Tatili', 750.25);
    UPDATE card SET current_debt = current_debt + 750.25 WHERE card_id = card_id_credit_88;

    -- 5. adım
    INSERT INTO transaction(card_id, transaction_type_id, description, amount)
    VALUES(card_id_credit_87, transaction_type_expense_id, 'Pandemi', 15.50);
    UPDATE card SET current_debt = current_debt + 15.50 WHERE card_id = card_id_credit_87;

    -- 6. adım
    INSERT INTO transaction(card_id, transaction_type_id, description, amount)
    VALUES(card_id_account_89, transaction_type_deposit_id, 'Hesabınıza para yatırıldı', 1500.00);
    UPDATE card SET balance = balance + 1500.00 WHERE card_id = card_id_account_89;

    -- 7. adım
    INSERT INTO transaction(card_id, transaction_type_id, description, amount)
    VALUES(card_id_account_89, transaction_type_withdrawal_id, 'Hesabınızdan para çekildi', 350.00);
    UPDATE card SET balance = balance - 350.00 WHERE card_id = card_id_account_89;

    -- 8. adım
    INSERT INTO card(customer_id, account_id, card_type_id, card_number, expiry_month, expiry_year, ccv)
    VALUES(p_customer_id, p_account_id, card_type_account_id, '1234987654645490', 12, 2028, '987')
    RETURNING card_id INTO card_id_account_90;

    -- 9. adım: Hata alması beklenen ve yakalanacak olan kısım
    BEGIN
        INSERT INTO transaction(card_id, transaction_type_id, description, amount)
        VALUES(card_id_account_90, transaction_type_withdrawal_id, 'Hesabınızdan para çekildi (2. kart)', 125.00);
        UPDATE card SET balance = balance - 125.00 WHERE card_id = card_id_account_90;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE '9. adım atlandı ve hata yakalandı: %', SQLERRM;
            -- `SQLERRM`, hata mesajını içerir.
    END;

    -- 10. adım
    UPDATE card SET balance = balance - 750.25 WHERE card_id = card_id_account_89;
    UPDATE card SET current_debt = current_debt - 750.25 WHERE card_id = card_id_credit_88;
    INSERT INTO transaction(card_id, transaction_type_id, description, amount)
    VALUES (card_id_account_89, transaction_type_payment_id, 'Kredi Kartı Borç Ödemesi', 750.25);
    
END;
$$;