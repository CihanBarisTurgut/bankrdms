CREATE OR REPLACE FUNCTION get_list_transaction_type_func()
RETURNS SETOF transaction_type
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM transaction_type
    ORDER BY transaction_type_id;
END;
$$;
