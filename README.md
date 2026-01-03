Project Setup Instructions
Prerequisites

0. Make sure you have Python 3 and Flutter installed and in PATH

Before proceeding, verify that both Python 3 and Flutter are properly installed and accessible from your command line:
Verify Python 3 Installation
bash

[python3 --version]

Expected output: Python 3.x.x
Verify Flutter Installation
bash

[flutter --version]

Expected output: Flutter version information
Check PATH Configuration

If either command returns "command not found" or similar error, you need to:

    Install the missing software

    Add it to your system PATH

Installation Links:

    Python 3: Download from python.org

    Flutter: Installation guide

Setup Steps
1. Create a Python Virtual Environment

Create a virtual environment named venv in your project directory:
bash

[python3 -m venv .venv]

2. Install the requirements.txt in that Environment
Step 2.1: Activate the Virtual Environment

For macOS and Linux:
bash

source .venv/bin/activate

For Windows (Command Prompt):
bash

.venv\Scripts\activate.bat

For Windows (PowerShell):
bash

venv\Scripts\Activate.ps1

You'll know the virtual environment is activated when you see (venv) at the beginning of your command line prompt.
Step 2.2: Install Dependencies

With the virtual environment activated, install all required packages:
bash

[pip install -r requirements.txt]

Note: If requirements.txt doesn't exist, you may need to:

    Create it with your project dependencies

    Or install packages manually with pip install package_name

3. Run the Flutter Application
bash

flutter run

Alternative Flutter Run Options:

    Run on a specific device:
    bash

flutter run -d device_id

Run in release mode:
bash

flutter run --release

Run for web (if configured):
bash

flutter run -d chrome

Common Issues and Solutions
Virtual Environment Issues

Problem: python3 -m venv venv fails
Solution: Install venv module
bash

# Ubuntu/Debian
sudo apt install python3-venv

# macOS with Homebrew
brew install python3

# Windows (reinstall Python with "Add Python to PATH" checked)

Problem: Activation script fails on Windows
Solution: Run PowerShell as Administrator and set execution policy:
powershell

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

Flutter Issues

Problem: flutter run shows no devices
Solution:
bash

# Check connected devices
flutter devices

# If no devices appear:
# - For Android: Start an emulator from Android Studio
# - For iOS: Open Simulator from Xcode
# - For web: Enable web support: flutter config --enable-web

Problem: Flutter doctor shows issues
Solution: Run:
bash

flutter doctor

Follow the recommendations provided by the command to fix missing dependencies.
Requirements.txt Issues

Problem: pip install -r requirements.txt fails
Solution:
bash

# Upgrade pip first
pip install --upgrade pip

# Try installing with verbose output
pip install -r requirements.txt -v

# If specific package fails, install it separately
pip install problematic_package

Project Structure Summary
text

pgplayer_flutter/
├── .venv/                    # Python virtual environment (created)
├── requirements.txt         # Python dependencies
├── pubspec.yaml            # Flutter dependencies
├── lib/                    # Flutter source code
├── main.py                 # Python main file (if applicable)
└── ... other project files

Important Notes

    Always activate the virtual environment before running Python scripts

    The venv folder should be in your .gitignore file

    Keep Python and Flutter updated regularly

    For production deployment, use:
    bash
