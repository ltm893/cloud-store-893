-- Sample seed data for Postgres (Java Rocks coffee store)

BEGIN;

INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price)
VALUES
  ('872000000001', 'Java Rocks House Drip 12oz', 'made coffee', 'Java Rocks Bar', 3.75, NULL),
  ('872000000002', 'Java Rocks Latte 16oz', 'made coffee', 'Java Rocks Bar', 5.50, NULL),
  ('872000000003', 'Java Rocks Cappuccino 12oz', 'made coffee', 'Java Rocks Bar', 5.25, NULL),
  ('872000000004', 'Java Rocks Cold Brew 16oz', 'made coffee', 'Java Rocks Bar', 4.95, 4.25),
  ('872000000005', 'Java Rocks Double Espresso', 'made coffee', 'Java Rocks Bar', 3.50, NULL),
  ('872000000101', 'Java Rocks Colombia Supremo 12oz', 'coffee beans', 'Java Rocks Roastery', 16.99, NULL),
  ('872000000102', 'Java Rocks Ethiopia Yirgacheffe 12oz', 'coffee beans', 'Java Rocks Roastery', 18.99, NULL),
  ('872000000103', 'Java Rocks Espresso Roast 1lb', 'coffee beans', 'Java Rocks Roastery', 17.49, 15.99),
  ('872000000104', 'Java Rocks Decaf Swiss Water 12oz', 'coffee beans', 'Swiss Water Process Co.', 15.99, NULL),
  ('872000000201', 'Java Rocks 16oz Travel Tumbler', 'go cups', 'Pacific Drinkware Co.', 12.99, NULL),
  ('872000000202', 'Java Rocks 20oz Go Cup', 'go cups', 'Pacific Drinkware Co.', 14.99, NULL),
  ('872000000203', 'Java Rocks 24oz Cold Cup', 'go cups', 'Evergreen Reusables', 11.99, 9.99),
  ('872000000301', 'Java Rocks Logo Tee — Navy', 'clothes', 'Bella+Canvas', 24.99, NULL),
  ('872000000302', 'Java Rocks Logo Tee — Black', 'clothes', 'Bella+Canvas', 24.99, NULL),
  ('872000000303', 'Java Rocks Hoodie — Charcoal', 'clothes', 'Independent Trading Co.', 49.99, NULL),
  ('872000000304', 'Java Rocks Barista Apron', 'clothes', 'Chef Works', 29.99, NULL);

INSERT INTO products (barcode, name, product_type, manufacturer, price, sale_price, tax_exempt)
VALUES
  ('872000000401', 'Crystal Spring 16.9oz Bottled Water', 'water', 'Crystal Spring Beverages', 1.99, NULL, 1),
  ('872000000402', 'Crystal Spring 1L Bottled Water', 'water', 'Crystal Spring Beverages', 2.49, NULL, 1),
  ('872000000403', 'Crystal Spring Sparkling Water 12oz', 'water', 'Crystal Spring Beverages', 2.25, NULL, 1),
  ('872000000404', 'Crystal Spring Gallon Spring Water', 'water', 'Crystal Spring Beverages', 3.49, 2.99, 1);

INSERT INTO bulk_inventory (sku_key, name, quantity_on_hand, unit, reorder_point)
VALUES ('kitchen_beans', 'Kitchen bulk coffee beans', 8000, 'oz', 500);

INSERT INTO inventory_consumption_rules (product_type, bulk_sku_key, quantity_per_unit, unit)
VALUES ('made coffee', 'kitchen_beans', 1.5, 'oz');

UPDATE products
SET track_inventory = 1
WHERE product_type IN ('coffee beans', 'go cups', 'clothes', 'water');

INSERT INTO product_inventory (product_id, quantity_on_hand, reorder_point)
SELECT
  p.id,
  CASE p.product_type
    WHEN 'coffee beans' THEN 30
    WHEN 'go cups' THEN 20
    WHEN 'clothes' THEN 10
    WHEN 'water' THEN 48
    ELSE 0
  END,
  CASE p.product_type
    WHEN 'coffee beans' THEN 5
    WHEN 'go cups' THEN 3
    WHEN 'clothes' THEN 2
    WHEN 'water' THEN 12
    ELSE 0
  END
FROM products p
WHERE p.track_inventory = 1;

INSERT INTO customers (name, email, phone, address_line1, city, state, postal_code, card_fake, member_code)
VALUES
  (
    'Alex Rivera',
    'alex.rivera@example.com',
    '555-010-8720',
    '42 Roaster Row',
    'Portland',
    'OR',
    '97209',
    '4532015112830366',
    'JR-893'
  ),
  (
    'Jordan Guest',
    'jordan@example.com',
    '555-010-0001',
    '100 Public Rd',
    'Portland',
    'OR',
    '97201',
    '4111111111111111',
    NULL
  );

COMMIT;
