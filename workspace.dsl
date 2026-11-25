workspace "Smart Coworking Space Booking" "Модель C4 системи бронювання робочих місць і зон у студентському просторі (ЛР № 8)" {
  !impliedRelationships false
  model {
    // Особи
    user = person "Користувач" "Студент або представник студентської команди"
    admin = person "Адміністратор коворкінгу" "Чергова особа, що контролює порядок у студентському просторі"
    // Зовнішні системи
    sso = softwareSystem "University OAuth / SSO Provider" "Автентифікація за корпоративним акаунтом університету" "External"
    mail = softwareSystem "University Mail Service" "Поштовий сервіс університету" "External"
    scb = softwareSystem "Smart Coworking Space Booking" "Мапа простору, бронювання без конфліктів, Check-in, автоскасування неявок, адміністрування" {
      web = container "Веб-застосунок" "Мапа місць, бронювання, Check-in, особистий кабінет, панель адміністратора; адаптивний інтерфейс" "TypeScript, React (SPA)" "Browser"
      api = container "Booking API" "Логіка прецедентів, перевірка конфліктів, автентифікація й авторизація (модульний моноліт)" "Python, FastAPI" {
        group "Шар представлення" {
          authFilter = component "Фільтр автентифікації" "Перевіряє токен і роль користувача (UC-01)" "FastAPI dependency, PyJWT"
          placesCtl = component "Контролер місць" "Приймає запити мапи й фільтрації (UC-02, UC-03)" "FastAPI router"
          bookingCtl = component "Контролер бронювань" "Бронювання, особистий кабінет, Check-in (UC-04, UC-06, UC-07, UC-08)" "FastAPI router"
          adminCtl = component "Контролер адміністрування" "Моніторинг, скасування, блокування (UC-09, UC-10, UC-11)" "FastAPI router"
        }
        group "Шар застосунку й домену" {
          mapSvc = component "Сервіс карти місць" "Стан і фільтри місць (UC-02, UC-03)" "Python-модуль"
          conflictSvc = component "Сервіс конфліктів" "Перетин слота з бронюваннями й блокуваннями (UC-05)" "Python-модуль"
          bookingMgr = component "Керування бронюваннями" "Бронювання, Check-in, скасування (UC-04, UC-07, UC-08, UC-10)" "Python-модуль"
        }
        group "Шар інфраструктури" {
          repos = component "Репозиторії MySQL" "Реалізують ІРепозиторійБронювань та ІРепозиторійМісць" "SQLAlchemy"
          rules = component "Конфігурація правил" "Ліміти слота, вікно Check-in (QR-05)" "YAML, Python"
          mailAdapter = component "Адаптер поштової служби" "Реалізує ІСповіщення" "Python, smtplib"
        }
      }
      db = container "База даних coworking_booking" "Користувачі, зони, місця, бронювання, Check-in, журнал скасувань, блокування" "MySQL 8, InnoDB" "Database"
      sched = container "Планувальник неявок" "Автоскасовує бронювання без Check-in через 15 хв після початку слота (FR-10)" "Python, APScheduler (фоновий процес)"
    }
    // Рівень 1 - системний контекст (без технологій)
    user -> scb "Шукає й бронює місця, підтверджує присутність, скасовує власні бронювання"
    admin -> scb "Переглядає активні бронювання, скасовує їх із причиною, блокує місця"
    scb -> sso "Перевіряє особу користувачів"
    scb -> mail "Надсилає підтвердження бронювання й повідомлення про скасування"
    mail -> user "Доставляє листи користувачу"
    // Рівень 2 - контейнери
    user -> web "Шукає, бронює, підтверджує присутність" "HTTPS"
    admin -> web "Контролює бронювання, блокує місця" "HTTPS"
    web -> sso "Перенаправляє користувача на вхід" "OIDC/HTTPS"
    web -> api "Викликає API з токеном доступу" "JSON/HTTPS"
    api -> sso "Отримує ключі перевірки токенів" "OIDC/HTTPS (JWKS)"
    api -> db "Читає й записує дані" "SQL/TCP"
    api -> mail "Надсилає підтвердження й повідомлення про скасування" "SMTP/TLS" "Async"
    sched -> db "Знаходить прострочені бронювання, позначає неявку" "SQL/TCP"
    sched -> mail "Надсилає попередження про автоскасування" "SMTP/TLS" "Async"
    // Рівень 3 - компоненти Booking API
    web -> authFilter "Надсилає запити з токеном" "JSON/HTTPS"
    authFilter -> sso "Отримує відкриті ключі" "OIDC/HTTPS (JWKS)"
    authFilter -> placesCtl "Передає перевірений запит"
    authFilter -> bookingCtl "Передає перевірений запит"
    authFilter -> adminCtl "Передає перевірений запит"
    placesCtl -> mapSvc "Викликає"
    bookingCtl -> bookingMgr "Викликає"
    adminCtl -> bookingMgr "Викликає"
    bookingMgr -> conflictSvc "Перевіряє конфлікт"
    bookingMgr -> repos "Зберігає бронювання й скасування"
    bookingMgr -> rules "Читає ліміти й вікно Check-in"
    bookingMgr -> mailAdapter "Просить надіслати лист" "" "Async"
    mapSvc -> repos "Читає місця й бронювання"
    conflictSvc -> repos "Читає бронювання й блокування"
    repos -> db "Читає й записує дані" "SQL/TCP"
    mailAdapter -> mail "Надсилає листи" "SMTP/TLS" "Async"
    // Розгортання
    prod = deploymentEnvironment "Production" {
      deploymentNode "Пристрій користувача" "" "ПК або смартфон, веб-браузер" {
        webInst = containerInstance web
      }
      deploymentNode "Дата-центр університету" "" "Мережа кампусу" {
        deploymentNode "Сервер застосунків" "" "Ubuntu Server LTS, Docker Engine" {
          proxy = infrastructureNode "Зворотний проксі" "TLS, статичні файли SPA, маршрутизація /api" "nginx"
          apiInst = containerInstance api
          schedInst = containerInstance sched
        }
        deploymentNode "Сервер бази даних" "" "Ubuntu Server LTS" {
          deploymentNode "СКБД" "" "MySQL 8 Community Server" {
            dbInst = containerInstance db
          }
        }
      }
    }
    webInst -> proxy "Завантажує SPA й надсилає запити до API" "HTTPS, порт 443"
    proxy -> apiInst "Передає запити до API" "HTTP, порт 8000"
  }
  views {
    systemContext scb "Context" "Діаграма системного контексту" {
      include *
      autoLayout lr
    }
    container scb "Containers" "Діаграма контейнерів" {
      include *
      // зв'язок показано на діаграмі контексту
      exclude relationship==mail->user
      autoLayout tb
    }
    component api "Components" "Діаграма компонентів контейнера Booking API" {
      include *
      // зв'язок показано на діаграмі контейнерів
      exclude relationship==web->sso
      autoLayout tb
    }
    dynamic scb "UC04" "Динамічна діаграма UC-04 «Забронювати робоче місце»" {
      user -> web "Підтверджує бронювання обраного місця й слота"
      web -> api "Надсилає запит на бронювання з токеном"
      api -> db "Читає бронювання й блокування місця на слот (UC-05)"
      api -> db "Зберігає бронювання зі статусом «заплановано»"
      api -> mail "Надсилає email-підтвердження"
      mail -> user "Доставляє підтвердження користувачу"
      autoLayout lr
    }
    deployment scb prod "Deployment" "Діаграма розгортання, середовище Production" {
      include *
      // запити від браузера проходять через зворотний проксі
      exclude relationship==webInst->apiInst
      autoLayout lr
    }
    styles {
      element "Element" {
        color #ffffff
      }
      element "Person" {
        shape Person
        background #08427b
      }
      element "Software System" {
        background #438dd5
      }
      element "External" {
        background #8b8b8b
      }
      element "Container" {
        background #438dd5
      }
      element "Browser" {
        shape WebBrowser
      }
      element "Database" {
        shape Cylinder
      }
      element "Component" {
        background #b7d6f4
        color #000000
      }
      element "Infrastructure Node" {
        background #e5e5e5
        color #000000
      }
      relationship "Relationship" {
        style dashed
      }
      relationship "Async" {
        style dotted
      }
    }
  }
}
