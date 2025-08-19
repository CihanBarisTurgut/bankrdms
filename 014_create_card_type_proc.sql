CREATE OR REPLACE PROCEDURE create_card_type_proc(
    p_type_name VARCHAR,
    p_description VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN

    IF EXISTS (SELECT 1 FROM card_type WHERE type_name = p_type_name) THEN
        RAISE EXCEPTION 'Bu kart tipi zaten mevcut: %', p_type_name;
    ELSE
        INSERT INTO card_type(type_name, description)
        VALUES (p_type_name, p_description);

        RAISE NOTICE 'Yeni kart tipi başarıyla oluşturuldu: %', p_type_name;
    END IF;
END;
$$;
