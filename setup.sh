#!/bin/bash

# Name of the virtual environment
VENV_NAME=".venv"

# Check if Python is installed
if ! command -v python3 &> /dev/null
then
    echo "Python3 is not installed. Please install Python3 first."
    exit 1
fi

# Check if pip is installed
if ! command -v pip3 &> /dev/null
then
    echo "pip is not installed. Installing pip..."
    sudo apt update
    sudo apt install -y python3-pip
fi

# Check if virtualenv is installed
if ! python3 -m virtualenv --version &> /dev/null
then
    echo "virtualenv is not installed. Installing virtualenv..."
    pip3 install --user virtualenv
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_NAME" ]; then
    echo "Creating virtual environment '$VENV_NAME'..."
    python3 -m venv $VENV_NAME
else
    echo "Virtual environment '$VENV_NAME' already exists."
fi

# Activate the virtual environment
source $VENV_NAME/bin/activate

# Install packages from requirements.txt if it exists
if [ -f "requirements.txt" ]; then
    echo "Installing packages from requirements.txt..."
    pip install --upgrade pip
    pip install -r requirements.txt
else
    echo "requirements.txt not found. No packages installed."
fi

echo "Setup complete. Virtual environment '$VENV_NAME' is ready."
