-- TRANSACTION EXAMPLE FOR PATS DATABASE
--
-- by Mallory Hayase and Weikun Liang
--

BEGIN TRANSACTION;
--Create Visit--
INSERT INTO visits (pet_id, date, weight)
VALUES (173, current_date, 39);
SAVEPOINT create_visit;
--Create treatment--
INSERT INTO treatments (visit_id, procedure_id, successful)
VALUES(currval(pg_get_serial_sequence('visits', 'id')), (SELECT id FROM procedures WHERE name ILIKE 'examination'), 't');
SAVEPOINT create_treatment;
--Create visit_medicines # 1 --
INSERT INTO visit_medicines (visit_id, medicine_id, units_given)
VALUES (currval(pg_get_serial_sequence('visits', 'id')), 3, 500);
SAVEPOINT create_vm1;
--Create visit_medicines #2 --
INSERT INTO visit_medicines (visit_id, medicine_id, units_given)
VALUES (currval(pg_get_serial_sequence('visits', 'id')), 5, 200);
SAVEPOINT create_vm2;
COMMIT TRANSACTION;