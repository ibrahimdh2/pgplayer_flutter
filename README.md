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

[flutter run]

Alternative Flutter Run Options:

    Run on a specific device:
    bash


Run in release mode:
bash

flutter run --release
