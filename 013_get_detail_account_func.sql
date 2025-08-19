CREATE OR REPLACE FUNCTION get_detail_account_func(p_account_id INT)
RETURNS SETOF account
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT * 
    FROM account
    WHERE account_id = p_account_id;
END;
$$;
