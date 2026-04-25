Write-Host "Installing backend dependencies..."

Set-Location smart_vehicle_backend

python -m venv .venv
.\.venv\Scripts\Activate.ps1

python -m pip install --upgrade pip
python -m pip install -r requirements.txt

deactivate

Write-Host "Installing Flutter dependencies..."

Set-Location ..\smart_vehicle_app
flutter pub get

Write-Host "Installation finished."