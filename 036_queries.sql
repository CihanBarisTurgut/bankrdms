-- Müşterilerin yaşını hesaplama
SELECT customer_name, EXTRACT(YEAR FROM AGE(birth_date)) AS yas
FROM customer;

SELECT * FROM ACCOUNT;

-- Hesabı olan müşterilerin adını getir
SELECT c.customer_name FROM customer c 
JOIN account a ON c.customer_id=a.customer_id
GROUP BY c.customer_name; --duplicate için

select*from card
-- hesap kartı bulunmayan hesaplar
SELECT c.customer_id,c.customer_name,a.account_name,cc.card_id,cc.account_id,cc.card_type_id FROM customer c
JOIN account a ON c.customer_id=a.customer_id
LEFT JOIN card cc ON a.customer_id=cc.customer_id
AND cc.card_type_id=1
--WHERE cc.card_id IS NULL

select * from card
--kredi kartı olan veya olmayan kartları getir -kredi kartı tip id 2 ,banka kartı 1
SELECT c.customer_id,c.customer_name,cc.account_id,cc.card_id,cc.card_type_id FROM customer c
LEFT JOIN card cc ON c.customer_id=cc.customer_id
AND cc.card_type_id=2
--WHERE cc.card_id IS NULL   --NULL kullanmak yerine WHERE NOT EXIST ile sorgu daha performanslı

-- kredi kartı(2) banka kartı(1) bulunmayan müşteriler
SELECT c.customer_id, c.customer_name
FROM customer c
WHERE NOT EXISTS (
    SELECT 1
    FROM card cc
    WHERE cc.customer_id = c.customer_id
      AND cc.card_type_id = 2
);


-- hiç alışveriş yapmayan müşteriler
SELECT c.customer_id,c.customer_name FROM customer c
WHERE NOT EXISTS (
    SELECT 1
    FROM card cc
    JOIN transaction t ON cc.card_id = t.card_id
    WHERE cc.customer_id = c.customer_id
      AND t.transaction_type_id = 3
);

-- herhangi bir kartı olsa bile hiç işlem yapmamış hesap kartları
SELECT c.customer_id,c.customer_name,cc.card_id,cc.account_id,t.transaction_id FROM customer c
JOIN card cc ON c.customer_id=cc.customer_id
LEFT JOIN transaction t ON cc.card_id=t.card_id
WHERE t.transaction_id IS NULL





-- para yatırma işlemi yapan kullanıcıları ve tc'lerini getir
SELECT c.customer_name, c.tc_no, t.description FROM customer c
JOIN card cc ON c.customer_id=cc.customer_id
JOIN transaction t ON cc.card_id=t.card_id
WHERE transaction_type_id=1



-- Kart oluşturma, hesap kartı için account id girilir, kredi kartı için boş bırakılır
CALL create_card_proc(
    2::INT,                          -- p_customer_id
    NULL::INT,                          -- p_account_id
    2::INT,                          -- p_card_type_id account(1) credit(2)
    '1565168998001501'::VARCHAR(16), -- p_card_number
    12::SMALLINT,                    -- p_expiry_month
    2029::SMALLINT,                  -- p_expiry_year
    '123'::VARCHAR(3),               -- p_ccv
    10000.00::DECIMAL(10,2),          -- p_limit_amount
    0.00::DECIMAL(10,2),             -- p_current_debt
    0.00::DECIMAL(10,2),          -- p_balance
    NULL::VARCHAR(20)            -- p_status
);

-- Arda Güler'in kredi kartlarını ve limitlerini getir
SELECT c.customer_name,cc.card_number,cc.card_id,cc.limit_amount FROM customer c
JOIN card cc ON c.customer_id = cc.customer_id
WHERE c.customer_name='Arda Güler' AND cc.card_type_id=2-- cc.account_id IS NULL yerine soldakikullanım

-- Hangi işlemden kaç defa yapıldı
SELECT description, COUNT(*) as sayisi FROM transaction
GROUP BY description;

-- Sayısı 5'ten fazla yapılan işlemleri getir
SELECT description, COUNT(*) AS sayisi
FROM transaction
GROUP BY description
HAVING COUNT(*) > 5
ORDER BY sayisi DESC;

-- Hiç kartı olmayan müşteriler
SELECT c.customer_name
FROM customer c
LEFT JOIN card cc ON c.customer_id = cc.customer_id
WHERE cc.card_id IS NULL;

-- Hesap kartında 2000 ile 8000 lira arası para olan kullanıcıları isimleriyle getir
SELECT c.customer_name, cc.balance FROM customer c
JOIN card cc ON c.customer_id=cc.customer_id
WHERE cc.balance BETWEEN 2000 AND 8000

SELECT*FROM transaction



-- En çok işlem yapan müşteri
SELECT c.customer_name, COUNT(t.transaction_id) AS islem_sayisi
FROM customer c
JOIN card cc ON c.customer_id = cc.customer_id
JOIN transaction t ON cc.card_id = t.card_id
GROUP BY c.customer_name
ORDER BY islem_sayisi DESC
LIMIT 1;

-- En yüksek miktarda para yatırma işlemi yapan kullanıcı
SELECT c.customer_name,t.transaction_type_id,t.description,t.amount 
FROM customer c
JOIN card cc ON cc.customer_id=c.customer_id
JOIN transaction t ON t.card_id=cc.card_id
WHERE transaction_type_id=1
ORDER by t.amount DESC





-- para yatırma örneği
CALL deposit_to_account_card(6,1500.00)

-- para çekme örneği
CALL withdraw_from_account_card(11,3000.00)

-- para harcama örneği, kredi veya hesap kartı fark etmez, örn alışveriş vs.
CALL expense_money_by_card(7,3000.00,'Ayakkabı alışverişi')

-- kredi kartına borç yatırma örneği
CALL payment_to_credit_card('TR310001662660666606195509',2,3000.00)

-- para transfer örneği
CALL transfer_money_by_iban('TR950001002452772206195001','TR950001002452772206195001',150.00)
CALL transfer_money_by_iban('TR950001002452772206195001','TR310001662660666606195509',150.00)