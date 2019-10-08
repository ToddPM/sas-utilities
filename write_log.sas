OPTIONS NOSOURCE;
OPTION VARINITCHK = NOTE;

/***************************************************************************/
%LET log_directory = \\PATH\TO\LOG\FOLDER;
/*-------------------------------------------------------------------------*/
%LET program_name = PROGRAM_NAME_HERE;
/***************************************************************************/

%GLOBAL report_date time_start_save timestamp;

%MACRO date_and_time();
	%LET timestamp = %SYSFUNC(PUTN(%SYSFUNC(DATE()), yymmddn8.))%SYSFUNC(PUTN(%SYSFUNC(TIME()), TIME8.));
	%LET ts_date = %SUBSTR(&timestamp, 1, 8);
	%LET ts_hour = %SUBSTR(&timestamp, 9, 2);
	%IF (&ts_hour < 10 ) %THEN %DO;
		%LET ts_hour = 0&ts_hour;
	%END;
	%LET ts_minute = %SUBSTR(&timestamp, 12, 2);
	%LET ts_second = %SUBSTR(&timestamp, 15, 2);
	%LET timestamp = &ts_date.-&ts_hour.&ts_minute.&ts_second.;
	%LET report_date = %SYSFUNC(DATEPART(%SYSFUNC(DATETIME())), WORDDATE.);
%MEND date_and_time;
%date_and_time

/* This will be the final log file. */
%LET log_file = &log_directory\&program_name._&timestamp..log;
FILENAME SASlog "&log_file";

/* The temporary message log file. */
FILENAME progress "&log_directory\temp_messages_&timestamp..log";

/* tpm: comment out for development/testing. */
PROC PRINTTO LOG  = "&log_file" NEW;
RUN;

%PUT %SYSFUNC(REPEAT(=, 99));
%PUT ***  program start: %SYSFUNC(PUTN(%sysfunc(date()), MMDDYY10.)) %SYSFUNC(PUTN(%sysfunc(time()), TIMEAMPM11.));
%PUT ***  SYSUSERID = &SYSUSERID;
%PUT ***  _METAUSER = &_METAUSER;
%PUT ***  log_file = &log_file;
%PUT %SYSFUNC(REPEAT(=, 99));
%PUT;
%PUT;
%PUT %SYSFUNC(REPEAT(=, 33))[ SAS program code begins here ]%SYSFUNC(REPEAT(=, 33));
OPTIONS SOURCE;

/**************************************************************************************************/

%MACRO drop_table(dataset);
	%IF %SYSFUNC(EXIST(&dataset)) %THEN %DO;
		PROC SQL NOPRINT;
			DROP TABLE &dataset
		;
		QUIT;
	%END;
%MEND drop_table;

%MACRO initialize_variables();

%MEND initialize_variables;

%MACRO log_time(begin_end, message);
	/*======================================================
	***  Note the date and time of the beginning or end  ***
	***  of a program step or optionally, of a message.  ***
	*** ------------------------------------------------ ***
	***  Because the running log might "skip" lines if   ***
	***  they are written almost simultaneously,         ***
	***  maintain a data set log. At the end of the      ***
	***  program, this will replace the log that is      ***
	***  output a line at a time.                        ***
	======================================================*/
	%LET date_log = %SYSFUNC(DATETIME());
	%LET date_log_print = %SYSFUNC(DATEPART(&date_log), MMDDYY);
	%LET time_log = %SYSFUNC(TIMEPART(&date_log));
	%LET time_log_print = %SYSFUNC(TIMEPART(&time_log), TIME);

	%LET begin_end = %UPCASE(&begin_end);

	%IF ("&begin_end" = "BEGIN") %THEN %DO;
		%LET time_start_save = &time_log;
	%END;

	/* Save the line to the log data set. */
	PROC SQL NOPRINT;
	%IF ("&begin_end" = "BEGIN") %THEN %DO;
		INSERT INTO log_data
		SET entry = "========== &date_log_print &time_log_print -- &begin_end (&SYSPROCESSNAME) ==========";

		INSERT INTO log_data
		SET entry = "";
	%END;
	%ELSE %IF ("&begin_end" = "END") %THEN %DO;
		%LET duration_total = %SYSFUNC(INTCK(MINUTE, &time_start_save, &time_log));

		INSERT INTO log_data
		SET entry = "";

		%print_duration(&duration_total, (total duration), data set)

		INSERT INTO log_data
		SET entry = "";

		INSERT INTO log_data
		SET entry = "========== &date_log_print &time_log_print -- &begin_end (&SYSPROCESSNAME) ==========";
	%END;
	%ELSE %DO;
		INSERT INTO log_data
		SET entry = "[ &date_log_print &time_log_print ] %BQUOTE(&message)";
	%END;
	QUIT;

	/* Write the same line to the running log. */
	DATA _NULL_;
		FILE progress 
	%IF ("&begin_end" = "BEGIN") %THEN %DO;
			;
			PUT "========== &date_log_print &time_log_print -- &begin_end (&SYSPROCESSNAME) ==========";
			PUT ;
	%END;
	%ELSE %IF ("&begin_end" = "END") %THEN %DO;
			MOD;
		%LET duration_total = %SYSFUNC(INTCK(MINUTE, &time_start_save, &time_log));
			PUT ;
		%print_duration(&duration_total, (total duration), file)
			PUT ;
			PUT "========== &date_log_print &time_log_print -- &begin_end (&SYSPROCESSNAME) ==========";
	%END;
	%ELSE %DO;
			MOD;
			PUT "[ &date_log_print &time_log_print ] %BQUOTE(&message)";
	%END;
	RUN;
%MEND log_time;

%MACRO pluralize(item_count, single_item_name, plural_item_name, include_space);
	/*===========================================================================================
	***  Use the input number to determine whether to use the singular or plural descriptor.  ***
	---------------------------------------------------------------------------------------------
	***  example: %pluralize(&mouse_count, mouse, mice, true)                                 ***
	===========================================================================================*/
	%LET include_space = %LOWCASE(&include_space);

	%IF ("&item_count" = "1") %THEN %DO;
		%LET new_item_name = &single_item_name;
	%END;
	%ELSE %DO;
		%LET new_item_name = &plural_item_name;
	%END;

	%IF ("&include_space" = "true") %THEN %DO;
		&item_count &new_item_name
	%END;
	%ELSE %DO;
		&item_count.&new_item_name
	%END;
%MEND pluralize;

%MACRO print_duration(total_minutes, suffix, target);
	/*======================================================================================
	***  Print the specified duration, given in minutes, in terms of hours and minutes.  ***
	======================================================================================*/
	%LET target = %LOWCASE(&target);

	%LET count_hours = %SYSEVALF(&total_minutes / 60, INTEGER);
	%LET count_minutes = %SYSEVALF(&total_minutes - (&count_hours * 60));

	%IF ("&target" = "file") %THEN %DO;
		PUT "  [ %pluralize(&count_hours, hour, hours, true), %pluralize(&count_minutes, minute, minutes, true) ] &suffix";
	%END;
	%ELSE %DO;
		INSERT INTO log_data
		SET entry = "  [ %pluralize(&count_hours, hour, hours, true), %pluralize(&count_minutes, minute, minutes, true) ] &suffix";
	%END;
%MEND print_duration;

/**************************************************************************************************/

%drop_table(log_data)
DATA log_data;
	ATTRIB
		entry	LENGTH = $100.
	;
RUN;

/* Delete the empty row just created. */
PROC SQL NOPRINT;
	DELETE FROM log_data
;
QUIT;

/**************************************************************************************************/

%log_time(BEGIN)
%initialize_variables
%log_time(END)

/**************************************************************************************************/

OPTIONS NOSOURCE;
%PUT %SYSFUNC(repeat(=, 34))[ SAS program code ends here ]%SYSFUNC(repeat(=, 34));
%PUT;
%PUT;
%PUT %SYSFUNC(repeat(=, 99));
%PUT ***  program end: %SYSFUNC(putN(%SYSFUNC(date()), mmddyy10.)) %SYSFUNC(putN(%SYSFUNC(time()), timeAMPM11.));
%PUT %SYSFUNC(repeat(=, 99));
%PUT;
%PUT %SYSFUNC(repeat(=, 28));
%PUT ***  Message log follows  ***;
%PUT %SYSFUNC(repeat(=, 28));
%PUT;

PROC PRINTTO;
RUN;

OPTIONS SOURCE;

/* Add the message log to the end of the SAS log. */
DATA _NULL_;
	FILE SASlog MOD;
	SET log_data;
	PUT
		entry $100.
	;
RUN;

%drop_table(log_data)

/* Delete the temporary message log file. */
DATA _NULL_;
	IF (FEXIST("progress")) THEN
		rc = FDELETE("progress");
RUN;
