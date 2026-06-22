# Container Manager

Инструмент для управления Docker Compose файлами с использованием [Apple Container CLI](https://github.com/apple/container) — нативного средства запуска Linux-контейнеров на macOS через легковесные виртуальные машины.

Доступен в двух вариантах: **нативное macOS-приложение на Swift** и **веб-интерфейс на Python**.

---

## Возможности

- **Загрузка docker-compose.yaml** — drag & drop или выбор файла
- **Редактор compose** — встроенный YAML-редактор с сохранением и скачиванием
- **Выбор архитектуры** — ARM64 (по умолчанию) / AMD64
- **Авто-резолвинг реестра** — образы с одним `/` (owner/image) автоматически идут через ghcr.io
- **Pull образов** — скачивание всех образов из compose-файла через `container pull --platform`
- **Export в tar.gz** — сохранение образов через `container image save` + gzip для переноса на другие машины
- **Валидация связей** — проверка depends_on, links, конфликтов портов, сетей и volumes
- **Генерация sample.env** — автоматическое создание шаблона переменных окружения из всех сервисов
- **Оценка ресурсов** — расчёт потребления RAM и CPU на основе deploy.resources
- **Граф зависимостей** — визуализация связей между сервисами (веб-версия)
- **Управление логом** — копирование, очистка, выделение текста

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
bash scripts/build-app.sh
```

Это соберёт release-бинарник, сгенерирует иконку и упакует в `.app` бандл.

Или вручную:
```bash
cd ContainerManagerApp
swift build -c release
```

Запуск:
```bash
open "build/Container Manager.app"
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
- Список уникальных образов с отображением resolved-пути
- Маппинг портов
- Зависимости между сервисами

### 2. Резолвинг реестра

Образы автоматически маппятся на реестры:
- **Без `/`** (`nginx:alpine`) → Docker Hub (без изменений)
- **Один `/`** (`owner/image:tag`) → `ghcr.io/owner/image:tag` (GitHub Container Registry)
- **С реестром** (`ghcr.io/org/tool:v1`) → без изменений

### 3. Редактирование compose

Кнопка **Edit YAML** открывает встроенный редактор. Можно:
- Редактировать YAML прямо в приложении
- **Save & Re-parse** — сохранить и обновить все панели
- **Download YAML** — скачать отредактированный файл

### 4. Скачивание образов

Нажмите **Pull All** для скачивания всех образов. Образы будут загружены для выбранной архитектуры с учётом резолвинга реестра.

### 5. Экспорт в tar.gz

Нажмите **Export tar.gz** — каждый образ сохранится в отдельный `.tar.gz` файл. Удобно для:
- Переноса образов на изолированные серверы
- Резервного копирования
- Развёртывания без доступа к реестру

### 6. Проверка связей

Нажмите **Check** для валидации:
- depends_on и links на существование сервисов
- Конфликты портов на хосте
- Ссылки на сети и volumes
- Наличие image или build у каждого сервиса

### 7. Генерация sample.env

Нажмите **.env** для генерации шаблона переменных окружения.

### 8. Оценка ресурсов

Нажмите **Resources** для расчёта потребления ресурсов на основе `deploy.resources`.

## Структура проекта

```
├── ContainerManagerApp/            # Нативное Swift macOS-приложение
│   ├── Package.swift
│   └── Sources/ContainerManagerApp/
│       ├── ContainerManagerApp.swift   # Точка входа SwiftUI App
│       ├── ContentView.swift           # Основной интерфейс
│       ├── Models.swift                # Модели данных
│       ├── ComposeParser.swift         # Парсер docker-compose.yaml (Yams)
│       └── ContainerCLI.swift          # Обёртка над container CLI
├── app.py                          # Flask-сервер веб-версии
├── compose_parser.py               # Парсер compose (Python)
├── container_manager.py            # Обёртка CLI (Python)
├── templates/index.html            # Веб-интерфейс
├── static/                         # CSS + JS
├── scripts/                        # Сборка и генерация иконки
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

Проект использует [Apple Container CLI](https://github.com/apple/container) — инструмент от Apple для запуска Linux-контейнеров как легковесных виртуальных машин на Mac с Apple Silicon.

## Лицензия

Проприетарная лицензия. Подробности в файле [LICENSE](LICENSE).

Модификация кода, копирование и использование идей в качестве основы для других проектов запрещены без письменного согласования с правообладателем.
