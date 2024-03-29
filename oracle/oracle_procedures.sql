SET SERVEROUTPUT ON;

-- 1. shows information about help received by the given client
CREATE OR REPLACE PROCEDURE TOTAL_HELP_INFO
  (cl_id IN NUMBER)
AS
  count_1 NUMBER; -- to check if such client exists and if he got volunteerings
  count_2 NUMBER; -- to check if the client was helped and if he got donations

  no_such_client_exception EXCEPTION;
  no_help_exception EXCEPTION;
  donations_total NUMBER := 0;
  volunteerinngs_total NUMBER := 0;

  donation_size_temp NUMBER;
  help_id_temp NUMBER;
  CURSOR help_cursor IS
    SELECT id_help
    FROM HELP
    WHERE client = cl_id;

BEGIN
  SELECT COUNT(id_client) INTO count_1
  FROM CLIENT
  WHERE id_client = cl_id;
  IF count_1 < 1 THEN
    RAISE no_such_client_exception;
  END IF;

  SELECT COUNT(id_help) INTO count_2
  FROM HELP
  WHERE client = cl_id;
  IF count_2 < 1 THEN
    RAISE no_help_exception;
  END IF;

  OPEN help_cursor;
  LOOP
    FETCH help_cursor INTO help_id_temp;
    EXIT WHEN help_cursor%NOTFOUND;

    SELECT COUNT(id_donation) INTO count_1
    FROM DONATION
    WHERE id_help = help_id_temp;

    SELECT COUNT(id_volunteering) INTO count_2
    FROM VOLUNTEERING
    WHERE id_help = help_id_temp;

    IF count_1 > 0 THEN
      SELECT size_donation INTO donation_size_temp
      FROM DONATION
      WHERE id_help = help_id_temp;
      donations_total := donations_total + donation_size_temp;
    ELSIF count_2 > 0 THEN
      volunteerinngs_total := volunteerinngs_total + 1;
    END IF;
  END LOOP;
  CLOSE help_cursor;

  IF donations_total > 0 THEN
    DBMS_OUTPUT.PUT_LINE('In total the client received ' || donations_total || ' in donations');
  ELSE
    DBMS_OUTPUT.PUT_LINE('The client did not receive any donations');
  END IF;
  IF volunteerinngs_total > 0 THEN
    DBMS_OUTPUT.PUT_LINE('The client was helped by volunteers ' || volunteerinngs_total || ' times');
  ELSE
    DBMS_OUTPUT.PUT_LINE('The client was not helped by volunteers');
  END IF;
EXCEPTION
  WHEN no_such_client_exception THEN
  DBMS_OUTPUT.PUT_LINE('THERE IS NO CLIENT WITH ID ' || cl_id);
  WHEN no_help_exception THEN
  DBMS_OUTPUT.PUT_LINE('THE CLIENT WITH ID ' || cl_id || ' HAS NOT RECEIVED ANY HELP YET');
END;
/
--testing
INSERT INTO CLIENT(id_client, cl_name, cl_surname, cl_gender) VALUES(100, 'test', 'test', 'F');

INSERT INTO HELP(id_help, client) VALUES(100, 1);
INSERT INTO DONATION(id_donation, donor, id_help, size_donation) VALUES (100, 1, 100, 1000);
INSERT INTO VOLUNTEERING(ID_VOLUNTEERING, VOLUNTEER, id_help) VALUES (100, 1, 100);

SELECT * FROM VOLUNTEERING V
WHERE EXISTS (SELECT * FROM HELP WHERE id_help = V.id_help AND CLIENT = 1);

DELETE FROM VOLUNTEERING WHERE id_volunteering = 1;
DELETE FRM DONATION WHERE id_donation = 1;

ROLLBACK
EXECUTE TOTAL_HELP_INFO(1);

--2. equally distributes the donated money among people who need it
--   the donation is made by the specified donor, or from anonymous in case the donor's name isn't specified
CREATE OR REPLACE PROCEDURE DONATE_TO_EVERYONE_IN_NEED
  (arg_id_donor  NUMBER,
    donor_name VARCHAR2 DEFAULT 'ANONYMOUS', donor_surname VARCHAR2 DEFAULT 'ANONYMOUS',
    total_donation_size NUMBER)
AS
  tmp_donation_size NUMBER(10, 2);
  donation_left NUMBER := total_donation_size; -- used for calculating avg donation
  people_left NUMBER; -- used for calculating avg donation

  donor_count NUMBER;-- to check if there is such donor
  people_count NUMBER; -- used for checking if anybody needs help
  no_people_in_need_exception EXCEPTION;

  donor_id NUMBER := arg_id_donor; -- used because arg_id_donor may be null
  help_id NUMBER; -- for generating help id
  donation_id NUMBER; -- for generating donation id

  CURSOR people_in_need_cursor IS
    SELECT ID_CLIENT,
      CL_NEEDEDMONEY - (SELECT SUM(size_donation)
                        FROM HELP, DONATION
                        WHERE CLIENT = CLIENT.ID_CLIENT AND DONATION.ID_HELP = HELP.ID_HELP) NEEDED_SUM
    FROM CLIENT
    WHERE CL_NEEDEDMONEY > (SELECT SUM(size_donation)
                            FROM HELP, DONATION
                            WHERE CLIENT = CLIENT.ID_CLIENT AND DONATION.ID_HELP = HELP.ID_HELP)
    ORDER BY NEEDED_SUM;
  tmp_client people_in_need_cursor%ROWTYPE;

BEGIN
  -- check if anybody needs help
  SELECT COUNT(id_client) INTO people_count
  FROM CLIENT
  WHERE CL_NEEDEDMONEY > (SELECT SUM(size_donation)
                          FROM HELP, DONATION
                          WHERE CLIENT = CLIENT.ID_CLIENT AND DONATION.ID_HELP = HELP.ID_HELP);
  IF people_count < 1 THEN
    RAISE no_people_in_need_exception;
  END IF;
  people_left := people_count;

  -- check if the donor id is specified
  IF arg_id_donor IS NULL THEN
    SELECT NVL(MAX(id_donor) + 1, 1) INTO donor_id FROM DONOR;
    INSERT INTO DONOR (id_donor, d_name, d_surname) VALUES (donor_id, donor_name, donor_surname);
  ELSE
    -- insert donor record if there is no such yet
    SELECT COUNT(id_donor) INTO donor_count
    FROM DONOR
    WHERE id_donor = arg_id_donor;
    IF donor_count < 1 THEN
      INSERT INTO DONOR (id_donor, d_name, d_surname) VALUES (arg_id_donor, donor_name, donor_surname);
    END IF;
  END IF;

  OPEN people_in_need_cursor;
  LOOP
    FETCH people_in_need_cursor INTO tmp_client;
    EXIT WHEN people_in_need_cursor%NOTFOUND;

    tmp_donation_size := donation_left / people_left;

    IF tmp_donation_size > tmp_client.NEEDED_SUM THEN
      tmp_donation_size := tmp_client.NEEDED_SUM;
    END IF;

    SELECT NVL(MAX(id_help) + 1, 1) INTO help_id FROM HELP;
    INSERT INTO HELP (id_help, client) VALUES (help_id, tmp_client.ID_CLIENT);

    SELECT NVL(MAX(id_donation) + 1, 1) INTO donation_id FROM DONATION;
    INSERT INTO DONATION (id_donation, donor, size_donation, date_donation, id_help)
    VALUES (donation_id, donor_id, tmp_donation_size, SYSDATE,help_id);

    donation_left := donation_left - tmp_donation_size;
    people_left := people_left - 1;
  END LOOP;
  CLOSE people_in_need_cursor;

  -- printing the result
  IF donation_left > 0 THEN
    DBMS_OUTPUT.PUT_LINE('Everyone in need got necessary help, still ' || donation_left || ' left');
  ELSE
    DBMS_OUTPUT.PUT_LINE('All the donation was distributed among ' || people_count || ' clients');  
  END IF;

EXCEPTION
  WHEN no_people_in_need_exception THEN
  DBMS_OUTPUT.PUT_LINE('NO PEOPLE NEED MONETARY HELP AT THE MOMENT');
END;
/

-- testing
SELECT * FROM DONOR WHERE ID_DONOR = 100;
SELECT SUM(size_donation) FROM DONATION WHERE DONOR = 100;
EXECUTE DONATE_TO_EVERYONE_IN_NEED(1100);
EXECUTE DONATE_TO_EVERYONE_IN_NEED(100, 1100);
EXECUTE DONATE_TO_EVERYONE_IN_NEED(100, 'TEST', 'TEST', 1100);
ROLLBACK

-- query for finding clients who need monetary help
SELECT ID_CLIENT,
CL_NEEDEDMONEY - (SELECT SUM(size_donation)
                    FROM HELP, DONATION
                    WHERE CLIENT = CLIENT.ID_CLIENT AND DONATION.ID_HELP = HELP.ID_HELP) NEEDED_MONEY
FROM CLIENT
WHERE CL_NEEDEDMONEY > (SELECT SUM(size_donation)
                        FROM HELP, DONATION
                        WHERE CLIENT = CLIENT.ID_CLIENT AND DONATION.ID_HELP = HELP.ID_HELP)
ORDER BY NEEDED_MONEY;

--3. shows top 3 donations made in the given year
CREATE OR REPLACE PROCEDURE SHOW_TOP_DONATIONS
  (arg_year NUMBER)
AS
  CURSOR donations_curs IS
    SELECT ID_CLIENT, cl_name, CL_SURNAME, ID_DONOR, D_NAME, D_SURNAME, SIZE_DONATION, DATE_DONATION
    FROM CLIENT, HELP, DONATION, DONOR
    WHERE HELP.CLIENT = CLIENT.ID_CLIENT AND DONATION.ID_HELP = HELP.ID_HELP AND DONATION.DONOR = DONOR.ID_DONOR
          AND EXTRACT(YEAR FROM DATE_DONATION) = arg_year
    ORDER BY SIZE_DONATION DESC;
  donation donations_curs%ROWTYPE;
  donations_count NUMBER := 0; -- to show only top 3

  check_donations NUMBER; -- to check if any donations were made that year
  no_donations_made_exception EXCEPTION; -- raised in case there are no donations made that year
BEGIN
  -- check if there any donations were made
  SELECT COUNT(id_donation) INTO check_donations
  FROM DONATION
  WHERE EXTRACT(YEAR FROM DATE_DONATION) = arg_year;

  IF check_donations < 1 THEN
    RAISE no_donations_made_exception;
  ELSIF check_donations < 3 THEN
    DBMS_OUTPUT.PUT_LINE('Only ' || check_donations || ' were made that year:');
  END IF;

  OPEN donations_curs;
  LOOP
    EXIT WHEN donations_count > 2;
    FETCH donations_curs INTO donation;
    EXIT WHEN donations_curs%NOTFOUND;

    donations_count := donations_count + 1;

    DBMS_OUTPUT.PUT('#' || donations_count || ' the sum is ' || donation.SIZE_DONATION || ' received by ' || donation.CL_NAME || ' ' || donation.CL_SURNAME);

    IF donation.D_NAME = 'ANONYMOUS' OR donation.D_NAME IS NULL THEN
      DBMS_OUTPUT.PUT(', the donor is anonymous');
    ELSE
      DBMS_OUTPUT.PUT(', donated by ' || donation.D_NAME || ' ' || donation.D_SURNAME);
    END IF;
    DBMS_OUTPUT.PUT(' | ' || donation.DATE_DONATION);
    DBMS_OUTPUT.NEW_LINE;
  END LOOP;
  CLOSE donations_curs;

EXCEPTION
  WHEN no_donations_made_exception THEN
  DBMS_OUTPUT.PUT_LINE('NO DONATIONS WERE MADE THAT YEAR');
END;
/
-- testing
EXECUTE SHOW_TOP_DONATIONS(2010);
EXECUTE SHOW_TOP_DONATIONS(2000);
EXECUTE SHOW_TOP_DONATIONS(2017);

-- insert and check with 2018
EXECUTE SHOW_TOP_DONATIONS(2018);
SAVEPOINT before_inserting;

INSERT INTO HELP(ID_HELP, CLIENT) VALUES (101, 1);
INSERT INTO HELP(ID_HELP, CLIENT) VALUES (102, 2);
INSERT INTO HELP(ID_HELP, CLIENT) VALUES (103, 3);
INSERT INTO HELP(ID_HELP, CLIENT) VALUES (104, 4);
INSERT INTO HELP(ID_HELP, CLIENT) VALUES (105, 5);

INSERT INTO DONOR(ID_DONOR) VALUES (100);

INSERT INTO DONATION (ID_DONATION, DONOR, SIZE_DONATION, DATE_DONATION, ID_HELP) VALUES (101, 100, 9999, sysdate, 1);
INSERT INTO DONATION (ID_DONATION, DONOR, SIZE_DONATION, DATE_DONATION, ID_HELP) VALUES (102, 2, 8888, sysdate, 2);
INSERT INTO DONATION (ID_DONATION, DONOR, SIZE_DONATION, DATE_DONATION, ID_HELP) VALUES (103, 3, 7777, sysdate, 3);
INSERT INTO DONATION (ID_DONATION, DONOR, SIZE_DONATION, DATE_DONATION, ID_HELP) VALUES (104, 4, 5555, sysdate, 4);
INSERT INTO DONATION (ID_DONATION, DONOR, SIZE_DONATION, DATE_DONATION, ID_HELP) VALUES (105, 5, 4444, sysdate, 5);

ROLLBACK TO SAVEPOINT before_inserting;

-- query used in the cursor
SELECT ID_CLIENT, cl_name, CL_SURNAME, ID_DONOR, D_NAME, D_SURNAME, SIZE_DONATION, DATE_DONATION
    FROM CLIENT, HELP, DONATION, DONOR
    WHERE HELP.CLIENT = CLIENT.ID_CLIENT AND DONATION.ID_HELP = HELP.ID_HELP AND DONATION.DONOR = DONOR.ID_DONOR
          AND EXTRACT(YEAR FROM DATE_DONATION) = 2010
    ORDER BY SIZE_DONATION DESC;