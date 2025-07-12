CREATE TABLE Patient(
    Patient_ID INT PRIMARY KEY AUTO_INCREMENT,
    First_Name VARCHAR(255) NOT NULL,
    Last_Name VARCHAR(255) NOT NULL,
    Gender VARCHAR(255),
    Age INT,
    Tel_No INT(11),
    Email VARCHAR(255)
);

CREATE TABLE Supplier(
    Supplier_ID INT PRIMARY KEY AUTO_INCREMENT,
    Name VARCHAR(255) NOT NULL,
    Tel_No INT(11),
    Email VARCHAR(255)
);

CREATE TABLE Product(
    Product_ID INT PRIMARY KEY AUTO_INCREMENT,
    Product_Name VARCHAR(255) NOT NULL,
    Price INT NOT NULL,
    Product_Type VARCHAR(255) NOT NULL,
    Description VARCHAR(255),
    Supplier_ID INT,
    FOREIGN KEY (Supplier_ID) REFERENCES Supplier(Supplier_ID)
);

CREATE TABLE Patient_Order(
    Order_Number INT PRIMARY KEY AUTO_INCREMENT,
    Date DATE NOT NULL,
    Total_Price DECIMAL(10,2) NULL,
    Patient_ID INT NOT NULL,
    FOREIGN KEY (Patient_ID) REFERENCES Patient(Patient_ID)
);

CREATE TABLE Order_Detail(
    Order_Number INT NOT NULL,
    Product_ID INT NOT NULL,
    Quantity INT,
    Total_Price DECIMAL(10,2),
    PRIMARY KEY (Order_Number, Product_ID),
    FOREIGN KEY (Order_Number) REFERENCES Patient_Order(Order_Number),
    FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID)
);

CREATE TABLE Inventory(
    Product_ID INT PRIMARY KEY NOT NULL,
    Quantity INT NOT NULL,
    Expiry_Date DATE NOT NULL,
    FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID)
);

-- Drop foreign key constraints
ALTER TABLE Order_Detail DROP FOREIGN KEY order_detail_ibfk_1;
ALTER TABLE Inventory DROP FOREIGN KEY inventory_ibfk_1;

-- Modify columns (AUTO_INCREMENT)
ALTER TABLE Order_Detail MODIFY Order_Number INT AUTO_INCREMENT;

-- Recreate foreign key constraints
ALTER TABLE Order_Detail ADD FOREIGN KEY (Order_Number) REFERENCES Patient_Order(Order_Number);
ALTER TABLE Inventory ADD FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID);

-- TRIGGERS
-- ---------------------------------------------------

-- 1) Trigger to update inventory on order
DELIMITER //
CREATE TRIGGER update_inventory_on_order
AFTER INSERT ON Order_Detail
FOR EACH ROW
BEGIN
    DECLARE ordered_product_id INT;
    DECLARE ordered_quantity INT;

    -- Get the ordered product ID and quantity from the order details
    SELECT Product_ID, Quantity
    INTO ordered_product_id, ordered_quantity
    FROM Order_Detail
    WHERE Order_Number = NEW.Order_Number
    LIMIT 1;

    -- Subtract the ordered quantity from the inventory
    UPDATE Inventory
    SET Quantity = Quantity - ordered_quantity
    WHERE Product_ID = ordered_product_id;
END;
//
DELIMITER ;

-- 2) Trigger to calculate order detail total price
DELIMITER //
CREATE TRIGGER calculate_order_detail_total_price
BEFORE INSERT ON Order_Detail
FOR EACH ROW
BEGIN
    -- Calculate the total price for the current order detail
    SET NEW.Total_Price = (
        SELECT NEW.Quantity * p.Price
        FROM Product p
        WHERE p.Product_ID = NEW.Product_ID
    );
END;
//
DELIMITER ;

-- 3) Trigger to update total price in Patient_Order table
DELIMITER //
CREATE TRIGGER update_patient_order_total_price
AFTER INSERT ON Order_Detail
FOR EACH ROW
BEGIN
    DECLARE total DECIMAL(10,2);

    -- Calculate the total price for the current order
    SELECT SUM(Total_Price) INTO total
    FROM Order_Detail
    WHERE Order_Number = NEW.Order_Number;

    -- Update the total price in the Patient_Order table
    UPDATE Patient_Order
    SET Total_Price = total
    WHERE Order_Number = NEW.Order_Number;
END;
//
DELIMITER ;

-- 4) Trigger to prevent negative inventory
DELIMITER //
CREATE TRIGGER prevent_negative_inventory
BEFORE INSERT ON Order_Detail
FOR EACH ROW
BEGIN
    DECLARE available_quantity INT;

    SELECT Quantity INTO available_quantity
    FROM Inventory
    WHERE Product_ID = NEW.Product_ID;

    IF available_quantity < NEW.Quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient inventory for the product';
    END IF;
END;
//
DELIMITER ;

-- ------------------------------------------------

-- Procedures
-- ------------------------------------------------

-- 1) Get Patient Orders Procedure
DELIMITER //
CREATE PROCEDURE GetPatientOrders(IN p_patient_id INT)
BEGIN
    SET @patient_id = p_patient_id;
    PREPARE stmt FROM 'SELECT * FROM Patient_Order WHERE Patient_ID = ?';
    EXECUTE stmt USING @patient_id;
    DEALLOCATE PREPARE stmt;
END;
//
DELIMITER ;

-- 2) Get order history of a patient
DELIMITER //
CREATE PROCEDURE GetPatientOrderDetails(IN patient_id INT)
BEGIN
    SELECT
        po.Order_Number,
        po.Date,
        od.Product_ID,
        p.Product_Name,
        od.Quantity,
        od.Total_Price
    FROM Patient_Order po
    JOIN Order_Detail od ON po.Order_Number = od.Order_Number
    JOIN Product p ON od.Product_ID = p.Product_ID
    WHERE po.Patient_ID = patient_id;
END //
DELIMITER ;

-- 3) Update Product Price Procedure
DELIMITER //
CREATE PROCEDURE UpdateProductPrice(
    IN p_product_id INT,
    IN p_new_price INT
)
BEGIN
    UPDATE Product SET Price = p_new_price WHERE Product_ID = p_product_id;
END;
//
DELIMITER ;

-- 4) Create Order Procedure
DELIMITER //
CREATE PROCEDURE CreateOrder(
    IN p_patient_id INT,
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    DECLARE total_price DECIMAL(10,2);

    -- Insert into Patient_Order
    INSERT INTO Patient_Order (Date, Patient_ID)
    VALUES (CURDATE(), p_patient_id);

    SET @last_order_number = LAST_INSERT_ID();

    -- Insert into Order_Detail
    INSERT INTO Order_Detail (Order_Number, Product_ID, Quantity, Total_Price)
    VALUES (@last_order_number, p_product_id, p_quantity, 0);

    -- Calculate total price
    SELECT SUM(p.Price * od.Quantity) INTO total_price
    FROM Order_Detail od
    JOIN Product p ON od.Product_ID = p.Product_ID
    WHERE od.Order_Number = @last_order_number;

    -- Update total price in Order_Detail
    UPDATE Order_Detail
    SET Total_Price = total_price
    WHERE Order_Number = @last_order_number;

    -- Update total price in Patient_Order
    UPDATE Patient_Order
    SET Total_Price = total_price
    WHERE Order_Number = @last_order_number;
END;
//
DELIMITER ;

-- 5) Get product inventory
DELIMITER //
CREATE PROCEDURE GetProductInventory(IN p_product_id INT)
BEGIN
    SELECT Quantity, Expiry_Date
    FROM Inventory
    WHERE Product_ID = p_product_id;
END;
//
DELIMITER ;

-- -----------------------------------------------

-- Functions
-- -----------------------------------------------

-- Create function to get supplier info for a product
DELIMITER //
CREATE FUNCTION GetProductSupplierInfo(product_id INT) RETURNS VARCHAR(255)
BEGIN
    DECLARE supplier_info VARCHAR(255);
    SELECT CONCAT(s.Name, ', ', s.Tel_No, ', ', s.Email) INTO supplier_info
    FROM Product p
    JOIN Supplier s ON p.Supplier_ID = s.Supplier_ID
    WHERE p.Product_ID = product_id;
    RETURN supplier_info;
END //
DELIMITER ;


-- Function to get patient info
DELIMITER //
CREATE FUNCTION GetPatientInfo(patient_id INT) RETURNS VARCHAR(255)
BEGIN
    DECLARE patient_info VARCHAR(255);

    SELECT CONCAT(First_Name, ' ', Last_Name, ', ', Gender, ', Age: ', Age, ', Tel: ', Tel_No, ', Email: ', Email)
    INTO patient_info
    FROM Patient
    WHERE Patient_ID = patient_id
    LIMIT 1;

    RETURN patient_info;
END //
DELIMITER ;


-- function to get product detail
DELIMITER //
CREATE FUNCTION GetProductDetails(product_id INT) RETURNS VARCHAR(255)
BEGIN
    DECLARE product_info VARCHAR(255);
    SELECT CONCAT('Product: ', p.Product_Name, ', Type: ', p.Product_Type, ', Price: ', p.Price, ', Supplier: ', GetProductSupplierInfo(p.Product_ID)) INTO product_info
    FROM Product p
    WHERE p.Product_ID = product_id;
    RETURN product_info;
END //
DELIMITER ;
-- ----------------------------------------------------------------------------------------------------------------------------------------



-- Insert Statements To Test Out Code:

-- Insert data into Patient table
INSERT INTO Patient (First_Name, Last_Name, Gender, Age, Tel_No, Email)
VALUES
  ('John', 'Doe', 'Male', 30, 1234567890, 'john.doe@example.com'),
  ('Jane', 'Smith', 'Female', 25, 9876543210, 'jane.smith@example.com'),
  ('Alice', 'Johnson', 'Female', 22, 5555555555, 'alice.j@example.com'),
  ('Bob', 'Williams', 'Male', 35, 3333333333, 'bob.w@example.com'),
  ('Eva', 'Martin', 'Female', 28, 4444444444, 'eva.m@example.com'),
  ('Daniel', 'Clark', 'Male', 40, 6666666666, 'daniel.c@example.com'),
  ('Sophia', 'Taylor', 'Female', 29, 8888888888, 'sophia.t@example.com'),
  ('Michael', 'White', 'Male', 32, 7777777777, 'michael.w@example.com'),
  ('Olivia', 'Miller', 'Female', 24, 9999999999, 'olivia.m@example.com'),
  ('William', 'Moore', 'Male', 45, 1111111111, 'william.m@example.com');


-- Insert data into Supplier table
INSERT INTO Supplier (Name, Tel_No, Email)
VALUES
  ('ABC Supplier', 1112223333, 'abc@example.com'),
  ('XYZ Supplier', 4445556666, 'xyz@example.com'),
  ('LMN Supplier', 7778889999, 'lmn@example.com'),
  ('PQR Supplier', 3334445555, 'pqr@example.com'),
  ('UVW Supplier', 6667778888, 'uvw@example.com');


-- Insert data into Product table
INSERT INTO Product (Product_Name, Price, Product_Type, Description, Supplier_ID)
VALUES
  ('Product1', 20, 'TypeA', 'Description1', 1),
  ('Product2', 30, 'TypeB', 'Description2', 2),
  ('Product3', 25, 'TypeC', 'Description3', 3),
  ('Product4', 15, 'TypeD', 'Description4', 4),
  ('Product5', 40, 'TypeE', 'Description5', 5);

-- Insert data into Inventory table
INSERT INTO Inventory (Product_ID, Quantity, Expiry_Date)
VALUES
  (1, 50, '2024-12-31'),
  (2, 30, '2024-12-31'),
  (3, 20, '2025-06-30'),
  (4, 15, '2025-03-15'),
  (5, 25, '2025-05-20');

-- Insert data into Patient_Order table
INSERT INTO Patient_Order (Date, Patient_ID)
VALUES
  ('2024-01-01', 1),
  ('2024-02-01', 1),
  ('2024-03-01', 3),
  ('2024-04-01', 4),
  ('2024-05-01', 5),
  ('2024-06-01', 6),
  ('2024-07-01', 7),
  ('2024-08-01', 8),
  ('2024-09-01', 9),
  ('2024-10-01', 10);

-- Insert data into Order_Detail table
INSERT INTO Order_Detail (Order_Number, Product_ID, Quantity)
VALUES
  (1, 1, 3),
  (1, 2, 2),
  (2, 2, 1),
  (2, 3, 2),
  (3, 4, 1),
  (3, 5, 4),
  (4, 1, 2),
  (4, 3, 2),
  (5, 4, 1),
  (5, 5, 2),
  (6, 2, 3),
  (6, 4, 1),
  (7, 5, 2),
  (7, 1, 4),
  (8, 3, 2),
  (8, 4, 3),
  (9, 1, 1),
  (9, 5, 2),
  (10, 2, 10),
  (10, 3, 3);


