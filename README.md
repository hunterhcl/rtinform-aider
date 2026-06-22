# RTInform Container Manager

Инструмент для управления Docker Compose файлами с использованием [Apple Container CLI](https://github.com/apple/container) — нативного средства запуска Linux-контейнеров на macOS через легковесные виртуальные машины.

Доступен в двух вариантах: **нативное macOS-приложение на Swift** и **веб-интерфейс на Python**.

---

## Возможности

- **Загрузка docker-compose.yaml** — drag & drop или выбор файла
- **Выбор архитектуры** — ARM64 (по умолчанию) / AMD64
- **Pull образов** — скачивание всех образов из compose-файла через `container pull --platform`
- **Export в tar.gz** — сохранение образов через `container image save` + gzip для переноса на другие машины
- **Валидация связей** — проверка depends_on, links, конфликтов портов, сетей и volumes
- **Генерация sample.env** — автоматическое создание шаблона переменных окружения из всех сервисов
- **Оценка ресурсов** — расчёт потребления RAM и CPU на основе deploy.resources
- **Граф зависимостей** — визуализация связей между сервисами (веб-версия)

## Требования

### Системные
- macOS 14 (Sonoma) или новее
- Apple Silicon (для оптимальной работы)
- [Apple Container CLI](https://github.com/apple/container) — установить с [GitHub Releases](https://github.com/apple/container/releases)

### Для Swift-приложения
- Swift 5.9+
- Xcode 15+ или Swift toolchain

### Для веб-версии
- Python 3.10+
- pip

## Установка

### Swift-приложение (нативное macOS)

```bash
cd RTInformApp
swift build -c release
```

Бинарный файл будет в `.build/release/RTInformApp`.

Запуск:
```bash
swift run
# или
.build/release/RTInformApp
```

### Веб-версия

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

Откройте http://127.0.0.1:5150 в браузере.

## Использование

### 1. Загрузка compose-файла

Перетащите `docker-compose.yaml` в окно приложения или нажмите для выбора файла. Приложение автоматически распарсит файл и отобразит:
- Список сервисов с образами и портами
- Список уникальных образов
- Маппинг портов
- Зависимости между сервисами

### 2. Выбор архитектуры

Выберите целевую архитектуру в выпадающем списке:
- **ARM64** — для Apple Silicon и серверов на ARM
- **AMD64** — для x86_64 серверов и классических машин

### 3. Скачивание образов

Нажмите **Pull All** для скачивания всех образов из compose-файла. Образы будут загружены для выбранной архитектуры через `container pull --platform linux/<arch>`.

### 4. Экспорт в tar.gz

Нажмите **Export tar.gz** и выберите директорию для сохранения. Каждый образ будет сохранён в отдельный `.tar.gz` файл с именем, включающим архитектуру. Это удобно для:
- Переноса образов на изолированные серверы
- Резервного копирования
- Развёртывания без доступа к реестру

### 5. Проверка связей

Нажмите **Check** для валидации compose-файла:
- Проверка всех depends_on и links на существование сервисов
- Обнаружение конфликтов портов на хосте
- Проверка ссылок на сети и volumes
- Проверка наличия image или build у каждого сервиса

### 6. Генерация sample.env

Нажмите **.env** для генерации шаблона переменных окружения. Все переменные из всех сервисов будут собраны в один файл, сгруппированные по сервисам. Файл можно скопировать в буфер обмена или сохранить.

### 7. Оценка ресурсов

Нажмите **Resources** для расчёта потребления ресурсов. Используются значения из `deploy.resources.limits` и `deploy.resources.reservations`. Для сервисов без явных ограничений показываются значения по умолчанию (256 MB / 0.5 CPU).

## Структура проекта

```
rtinform-aider/
├── RTInformApp/                    # Нативное Swift macOS-приложение
│   ├── Package.swift
│   └── Sources/RTInformApp/
│       ├── RTInformApp.swift       # Точка входа SwiftUI App
│       ├── ContentView.swift       # Основной интерфейс
│       ├── Models.swift            # Модели данных
│       ├── ComposeParser.swift     # Парсер docker-compose.yaml (Yams)
│       └── ContainerCLI.swift      # Обёртка над container CLI
├── app.py                          # Flask-сервер веб-версии
├── compose_parser.py               # Парсер compose (Python)
├── container_manager.py            # Обёртка CLI (Python)
├── templates/index.html            # Веб-интерфейс
├── static/                         # CSS + JS
├── requirements.txt                # Python-зависимости
└── example-compose.yaml            # Пример для тестирования
```

## Технологии

| Компонент | Swift-приложение | Веб-версия |
|-----------|-----------------|------------|
| UI | SwiftUI | HTML/CSS/JS |
| Backend | Foundation/Process | Flask |
| YAML | [Yams](https://github.com/jpsim/Yams) | PyYAML |
| CLI | Apple Container | Apple Container |

## Связь с Apple Container

Проект использует [Apple Container CLI](https://github.com/apple/container) — инструмент от Apple для запуска Linux-контейнеров как легковесных виртуальных машин на Mac с Apple Silicon. В отличие от Docker Desktop:

- Каждый контейнер работает в отдельной микро-VM (изоляция на уровне гипервизора)
- Нативная реализация на Swift, оптимизированная под Apple Silicon
- Поддержка стандартных OCI-образов
- Минимальное потребление ресурсов

## Лицензия

[MIT License](LICENSE)
