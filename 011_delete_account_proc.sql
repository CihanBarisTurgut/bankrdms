CREATE OR REPLACE PROCEDURE delete_account_proc(
    p_account_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    p_deleted_at_account account.deleted_at%TYPE;
    p_customer_id INT;
    p_deleted_at_customer customer.deleted_at%TYPE;
BEGIN
    SELECT deleted_at, customer_id
    INTO p_deleted_at_account, p_customer_id
    FROM account
    WHERE account_id = p_account_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Hesap bulunamadı (ID: %)', p_account_id;
    END IF;

    IF p_deleted_at_account IS NOT NULL THEN
        RAISE EXCEPTION 'Bu hesap zaten silinmiş (ID: %)', p_account_id;
    END IF;
    
    SELECT deleted_at
    INTO p_deleted_at_customer
    FROM customer
    WHERE customer_id = p_customer_id;

    IF p_deleted_at_customer IS NOT NULL THEN
        RAISE EXCEPTION 'Hesabın ait olduğu müşteri silinmiş, hesap silinemez (Müşteri ID: %)', p_customer_id;
    END IF;

    UPDATE account
    SET deleted_at = NOW()
    WHERE account_id = p_account_id;

    RAISE NOTICE 'Hesap başarıyla soft delete edildi (ID: %)', p_account_id;
END;
$$;
