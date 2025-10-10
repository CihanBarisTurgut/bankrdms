CREATE OR REPLACE FUNCTION get_list_transaction_func()
RETURNS SETOF transaction
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM transaction
    ORDER BY transaction_date DESC;
END;
$$;