CREATE OR REPLACE PROCEDURE delete_customer_proc(
    p_customer_id INT
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
        RAISE NOTICE 'Bu müşteri daha önceden silinmiş, tekrar silinemez.';

    ELSE
        UPDATE customer
        SET deleted_at = NOW()
        WHERE customer_id = p_customer_id;

        RAISE NOTICE 'Müşteri silindi (ID: %)', p_customer_id;
    END IF;
END;
$$;
