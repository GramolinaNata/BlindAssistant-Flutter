# blindddd

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
# 👁️ Blind Assistant - Помощник для слабовидящих

## Описание
Мобильное приложение для помощи слабовидящим людям с использованием компьютерного зрения и голосового управления.

## Функции
- ✅ Распознавание 600+ объектов (YOLO)
- ✅ Голосовая биометрия для входа
- ✅ Анализ цветов и освещения
- ✅ Голосовые команды

## Технологии
- **Frontend**: Flutter/Dart
- **Backend**: Python (Flask)
- **AI**: YOLOv5, TensorFlow
- **Database**: PostgreSQL
- **Voice**: Google Speech-to-Text, gTTS

## Установка

### Backend
```bash
pip install flask ultralytics opencv-python psycopg2 gtts pydub
python app.py
```

### Frontend
```bash
flutter pub get
flutter run
```

## API Endpoints
- `POST /register_voice` - Регистрация голоса
- `POST /login_voice` - Вход по голосу
- `POST /process_frame` - Анализ кадра
- `GET /get_time` - Получить время

## База данных
См. [DATABASE_SCHEMA.md](DATABASE_SCHEMA.md)

## Разработчик
уважаемая Грамолина Наталья Антоновна