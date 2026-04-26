set -e

echo "Installing backend dependencies..."

cd smart_vehicle_backend

python3 -m venv .venv
source .venv/bin/activate

pip install --upgrade pip
pip install -r requirements.txt

echo "Installing Flutter dependencies..."

cd ../smart_vehicle_app
flutter pub get

echo "Installation finished."