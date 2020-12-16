-- Covid Shelter Category
insert into categories (id, created_at, updated_at, name, top_level, vocabulary, featured) values 
(1000010, '04-OCT-20', '04-OCT-20', 'Covid-shelter', 't', null, 'f');

-- Covid Shelter Subcategories
insert into categories (id, created_at, updated_at, name, top_level, vocabulary, featured) values
(1100041, '18-OCT-20', '18-OCT-20', 'We are a family and we need shelter', 'f', null, 'f');

insert into categories (id, created_at, updated_at, name, top_level, vocabulary, featured) values
(1100042, '18-OCT-20', '18-OCT-20', 'I am someone between 18-24 years old in need of shelter', 'f', null, 'f');

insert into categories (id, created_at, updated_at, name, top_level, vocabulary, featured) values
(1100043, '18-OCT-20',  '18-OCT-20', 'I am a single adult and I need shelter', 'f', null, 'f');

-- insert subcategories in Covid-shelter

insert into category_relationships (parent_id, child_id) values
(1000010, 1100041);

insert into category_relationships (parent_id, child_id) values
(1000010, 1100042);

insert into category_relationships (parent_id, child_id) values
(1000010, 1100043);

-- Insert services to Covid-shelter category

insert into categories_services (category_id, service_id) values (1000010, 2559);

insert into categories_services (category_id, service_id) values (1000010, 2560);

insert into categories_services (category_id, service_id) values (1000010, 228);

insert into categories_services (category_id, service_id) values (1000010, 49);

insert into categories_services (category_id, service_id) values (1000010,2872);

insert into categories_services (category_id, service_id) values (1000010, 2032);

insert into categories_services (category_id, service_id) values (1000010, 2030);

insert into categories_services (category_id, service_id) values (1000010, 719);

insert into categories_services (category_id, service_id) values (1000010, 2781);

insert into categories_services (category_id, service_id) values (1000010, 306);

insert into categories_services (category_id, service_id) values (1000010, 2670);

--insert services to subcategories

insert into categories_services (category_id, service_id) values (1100041, 2559);

insert into categories_services (category_id, service_id) values(1100041, 2560);

insert into categories_services (category_id, service_id) values(1100041, 228);

insert into categories_services (category_id, service_id) values(1100041, 49);

insert into categories_services (category_id, service_id) values (1100041, 2872);

insert into categories_services (category_id, service_id) values (1100042, 2032);

insert into categories_services (category_id, service_id) values (1100042, 2030);

insert into categories_services (category_id, service_id) values (1100042, 719);

insert into categories_services (category_id, service_id) values (1100042, 2781);

insert into categories_services (category_id, service_id) values (1100043, 306);

insert into categories_services (category_id, service_id) values (1100043, 2670);
