@echo off
cd /d "%~dp0"

if not exist "venv\Scripts\activate.bat" (
    echo Creating virtual environment...
    python -m venv venv
    if errorlevel 1 (
        echo Failed to create virtual environment!
        exit /b 1
    )
)

call venv\Scripts\activate.bat

if exist "requirements.txt" (
    echo Installing dependencies...
    pip install -r requirements.txt
    if errorlevel 1 (
        echo Failed to install dependencies!
        exit /b 1
    )
) else (
    echo Warning: requirements.txt not found!
)

python -m app.main
