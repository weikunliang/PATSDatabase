-- INDEXES FOR PATS DATABASE
--
-- by Weikun Liang & Mallory Hayase

-- Owner 

-- Note

CREATE INDEX notes_users_idx ON notes(user_id);

-- User

CREATE INDEX users_username_idx ON users(username);

-- Pet

CREATE INDEX pets_animals_idx ON pets(animal_id);
CREATE INDEX pets_owners_idx ON pets(owner_id);

-- Visit

CREATE INDEX visits_pets_idx ON visits(pet_id);

-- Animal

-- AnimalMedicine

CREATE INDEX animalmedicines_animals_idx ON animal_medicines(animal_id);
CREATE INDEX animalmedicines_medicines_idx ON animal_medicines(medicine_id);

-- VisitMedicine

CREATE INDEX visitmedicines_visits_idx ON visit_medicines(visit_id);
CREATE INDEX visitmedicines_medicines_idx ON visit_medicines(medicine_id);

-- Treatment

CREATE INDEX treatments_visits_idx ON treatments(visit_id);
CREATE INDEX treatments_procedures_idx ON treatments(procedure_id);

-- MedicineCost

CREATE INDEX medicinecosts_medicine_idx ON medicine_costs(medicine_id);

-- Medicine
-- Because of the need for full text searching on medicines(description), it is important to
-- add a GIN index on this field using the to_tsvector() function. 

CREATE INDEX medicines_idx ON medicines USING gin(to_tsvector('english', description));

-- Procedure

-- ProcedureCost

CREATE INDEX procedurecosts_procedure_idx ON procedure_costs(procedure_id);

