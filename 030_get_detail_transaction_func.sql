CREATE OR REPLACE FUNCTION get_detail_transaction_func(
    p_transaction_id INT
)
RETURNS transaction
LANGUAGE plpgsql
AS $$
DECLARE
    result_transaction transaction;
BEGIN
    SELECT *
    INTO result_transaction
    FROM transaction
    WHERE transaction_id = p_transaction_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'İlgili ID ile işlem bulunamadı (ID: %)', p_transaction_id;
        RETURN NULL;
    END IF;

    RETURN result_transaction;
END;
$$;