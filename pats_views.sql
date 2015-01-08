-- VIEWS FOR PATS DATABASE
--
-- by (student_1) & (student_2)
--
--

-- In terms of views, one view called 'owners_view' is to be created that joins 
-- owners, pets, and visits together.
--  In addition, the pet's animal_id is to be replaced with the animal name 
--  (which is more meaningful). 

create view owners_view as
	select o.id as "owner id", o.first_name, o.last_name, o.street, o.city, o.state, o.zip, o.phone, o.email, o.active as "owner active", 
			p.id as "pet id", p.name, a.name as "animal name", p.female, p.date_of_birth, p.active as "pet active", 
			v.id as "visit id", v.date, v.weight, v.overnight_stay, v.total_charge
	from owners o join pets p on o.id = p.owner_id join visits v on v.pet_id = p.id join animals a on a.id = p.animal_id;

 -- The second view is to be called 'medicine_views' 
 -- and connects information from the medicine, animal and cost tables together. 
 -- This view should also replace animal_id with the animal name. In terms of costs, 
 -- the only costs that need to appear are the current cost_per_unit for the medicine 
 -- (column should be called 'current cost') as well as the date the medicine's cost last changed

create view medicine_views as
	select m.id as "medicine id", m.name as "medicine name", m.description, m.stock_amount, m.unit, m.vaccine, 
			a.id as "animal id", a.name as "animal name", a.active as "animal active", am.recommended_num_of_units,
			mc.cost_per_unit as "current cost", mc.start_date
	from medicines m join animal_medicines am on m.id= am.medicine_id join animals a on am.animal_id=a.id join medicine_costs mc on mc.medicine_id=m.id
	where end_date is null;

