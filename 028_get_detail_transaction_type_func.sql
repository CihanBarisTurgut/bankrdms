CREATE OR REPLACE FUNCTION get_detail_transaction_type_func(
    p_transaction_type_id INT
)
RETURNS transaction_type
LANGUAGE plpgsql
AS $$
DECLARE
    result_type transaction_type;
BEGIN
    SELECT *
    INTO result_type
    FROM transaction_type
    WHERE transaction_type_id = p_transaction_type_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'İlgili ID ile işlem tipi bulunamadı (ID: %)', p_transaction_type_id;
        RETURN NULL;
    END IF;

    RETURN result_type;
END;
$$;
