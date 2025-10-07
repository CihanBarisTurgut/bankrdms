CREATE OR REPLACE PROCEDURE delete_card_proc(
    p_card_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    p_deleted_at_card TIMESTAMP;
    p_customer_id INT;
    p_account_id INT;
    p_card_type_id INT;
    p_deleted_at_customer TIMESTAMP;
    p_deleted_at_account TIMESTAMP;
BEGIN
    -- 1. Kartın varlığını ve ilişkili ID'leri kontrol et
    SELECT deleted_at, customer_id, account_id, card_type_id
    INTO p_deleted_at_card, p_customer_id, p_account_id, p_card_type_id
    FROM card
    WHERE card_id = p_card_id;

    -- Kart bulunamazsa hata 
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kart bulunamadı (ID: %)', p_card_id;
    END IF;

    -- Kart zaten silinmişse hata 
    IF p_deleted_at_card IS NOT NULL THEN
        RAISE EXCEPTION ' Bu kart zaten silinmiş (ID: %)', p_card_id;
    END IF;

    -- 2. Müşterinin silinme durumunu kontrol et
    SELECT deleted_at
    INTO p_deleted_at_customer
    FROM customer
    WHERE customer_id = p_customer_id;

    IF p_deleted_at_customer IS NOT NULL THEN
        RAISE EXCEPTION 'Kartın ait olduğu müşteri silinmiş, kart silinemez (Müşteri ID: %)', p_customer_id;
    END IF;

    -- 3. Eğer kart bir hesap kartıysa, hesabın silinme durumunu kontrol et
    IF EXISTS (SELECT 1 FROM card_type WHERE card_type_id = p_card_type_id AND type_name = 'ACCOUNT') THEN
        SELECT deleted_at
        INTO p_deleted_at_account
        FROM account
        WHERE account_id = p_account_id;
        
        IF p_deleted_at_account IS NOT NULL THEN
            RAISE EXCEPTION 'Bu kartın ait olduğu hesap silinmiş, kart silinemez (Hesap ID: %)', p_account_id;
        END IF;
    END IF;

    UPDATE card
    SET deleted_at = NOW()
    WHERE card_id = p_card_id;

    RAISE NOTICE 'Kart başarıyla silindi (ID: %)', p_card_id;

END;
$$;
