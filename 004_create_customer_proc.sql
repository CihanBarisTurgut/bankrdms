CREATE OR REPLACE PROCEDURE create_customer_proc(
    p_customer_name VARCHAR,
    p_tc_no CHAR,
    p_birth_date DATE,
    p_birth_place VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    p_is_soft_deleted BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM customer
        WHERE tc_no = p_tc_no AND deleted_at IS NOT NULL
    ) INTO p_is_soft_deleted;

   
    IF p_is_soft_deleted THEN
        UPDATE customer
        SET
            customer_name = p_customer_name,
            birth_date = p_birth_date,
            birth_place = p_birth_place,
            deleted_at = NULL 
        WHERE tc_no = p_tc_no;

        RAISE NOTICE 'Silinmiş kaydınız bulunmaktadır, bankamıza tekrar hoş geldiniz.';

    ELSE
        BEGIN
            INSERT INTO customer(customer_name, tc_no, birth_date, birth_place)
            VALUES(p_customer_name, p_tc_no, p_birth_date, p_birth_place);
        EXCEPTION
            
            WHEN unique_violation THEN
                RAISE NOTICE 'Bu T.C. kimlik numarası ile kayıtlı aktif bir müşteri zaten bulunmaktadır.';
            
            WHEN OTHERS THEN
                RAISE NOTICE 'Kullanıcı kaydedilemedi: %', SQLERRM;
        END;
    END IF;
END;
$$;
