CREATE OR REPLACE FUNCTION get_list_account_func()
RETURNS SETOF account
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM account;
END;
$$;
