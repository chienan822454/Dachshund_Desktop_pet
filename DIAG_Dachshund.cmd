@echo off
rem Dachshund Pet diagnostics: same safety check as START_Dachshund.cmd,
rem but the window stays open and shows any error.
call "%~dp0START_Dachshund.cmd" diag
