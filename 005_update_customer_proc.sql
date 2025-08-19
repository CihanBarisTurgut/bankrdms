CREATE OR REPLACE PROCEDURE update_customer_proc(
    p_customer_id INT,
    p_customer_name VARCHAR,
    p_tc_no CHAR,
    p_birth_date DATE,
    p_birth_place VARCHAR,
    p_risk_limit DECIMAL
)
LANGUAGE plpgsql
AS $$
DECLARE
    p_deleted_at customer.deleted_at%TYPE;
BEGIN
    SELECT deleted_at
    INTO p_deleted_at
    FROM customer
    WHERE customer_id = p_customer_id;

    IF NOT FOUND THEN
        RAISE NOTICE 'Böyle bir müşteri yok.';

    ELSIF p_deleted_at IS NOT NULL THEN
        RAISE NOTICE 'Bu müşteri silinmiştir, güncelleme yapılamaz.';

    ELSE
        UPDATE customer
        SET
            customer_name = p_customer_name,
            tc_no = p_tc_no,
            birth_date = p_birth_date,
            birth_place = p_birth_place,
            risk_limit = p_risk_limit
        WHERE customer_id = p_customer_id;

        RAISE NOTICE 'Güncelleme yapıldı.';
    END IF;
END;
$$;
