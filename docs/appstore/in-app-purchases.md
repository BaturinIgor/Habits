# Покупки Pro в App Store Connect

Код уже готов (`Habits/App/ProStore.swift`, `PaywallView.swift`). Осталось завести три товара в App Store Connect с точно такими ID.
ID ниже даны для идентификатора приложения `com.baturinigor.zenhab`. Если ты выберешь другой, замени начало: workflow подставит его в код сам.

| Что | Тип | Product ID | Reference Name |
|---|---|---|---|
| Pro на месяц | Auto-Renewable Subscription | `com.baturinigor.zenhab.pro.monthly` | Pro Monthly |
| Pro на год | Auto-Renewable Subscription | `com.baturinigor.zenhab.pro.yearly` | Pro Yearly |
| Pro навсегда | Non-Consumable | `com.baturinigor.zenhab.pro.lifetime` | Pro Lifetime |

Product ID нельзя поменять или использовать повторно даже после удаления, поэтому вводи их внимательно.

## Перед этим

Покупки не загрузятся в приложение, пока в **Business** (раньше Agreements, Tax, and Banking) не подписан **Paid Apps Agreement** и не заполнены банковский счёт и налоговые формы (W-8BEN для физлица не из США). Статус должен стать Active.

## Подписки

1. Monetization -> **Subscriptions** -> Subscription Groups -> "+". Reference Name группы: `ZenHab Pro`.
2. В группе создай две подписки из таблицы. Duration: 1 Month и 1 Year.
3. Для обеих одинаковый **Subscription Level** (1). Тогда переход с месяца на год работает как апгрейд внутри группы.
4. Цены (Subscription Prices): выбери базовую страну и цену, остальные Apple пересчитает. Ориентир для привычек: месяц $1.99, год $12.99 (в приложении автоматически покажется скидка "-46%"). Цены можно поменять в любой момент.
5. Пробный период (по желанию): Subscription Prices -> Introductory Offers -> Free, 1 week, для годовой подписки. Экран Pro уже показывает "Бесплатный период: 7 дней", если он есть.
6. **Localization** группы (App Store Localization): Display Name `ZenHab Pro`.
7. **Localization** каждой подписки: тексты ниже.
8. **Review Information**: скриншот экрана Pro (Настройки -> Трекер привычек Pro) с ценами. Подходит любой скриншот с iPhone. В Review Notes можно написать: `Open Settings > Habit Tracker Pro.`

## Покупка навсегда

Monetization -> **In-App Purchases** -> "+", тип **Non-Consumable**, ID из таблицы. Цена-ориентир $24.99. Локализация и скриншот для ревью такие же, как у подписок.

## Тексты (Display Name до 35 символов, Description до 55)

| Язык | Месяц | Год | Навсегда | Description (для всех трёх) |
|---|---|---|---|---|
| en-US | Pro Monthly | Pro Yearly | Pro Lifetime | Unlimited habits, goals, pause and exclusive pets |
| ru | Pro на месяц | Pro на год | Pro навсегда | Безлимит привычек, цели, пауза и редкие питомцы |
| de-DE | Pro monatlich | Pro jährlich | Pro für immer | Unbegrenzte Gewohnheiten, Ziele, Pause und mehr |
| fr-FR | Pro mensuel | Pro annuel | Pro à vie | Habitudes illimitées, objectifs, pause et plus |
| es-ES | Pro mensual | Pro anual | Pro para siempre | Hábitos ilimitados, metas, pausa y mascotas únicas |
| pt-BR | Pro mensal | Pro anual | Pro vitalício | Hábitos ilimitados, metas, pausa e bichinhos únicos |
| it | Pro mensile | Pro annuale | Pro a vita | Abitudini illimitate, obiettivi, pausa e altro |
| tr | Aylık Pro | Yıllık Pro | Ömür Boyu Pro | Sınırsız alışkanlık, hedefler, duraklatma ve dahası |
| pl | Pro miesięcznie | Pro rocznie | Pro na zawsze | Bez limitu nawyków, cele, pauza i więcej |
| id | Pro Bulanan | Pro Tahunan | Pro Selamanya | Kebiasaan tanpa batas, target, jeda, dan lainnya |
| zh-Hans | Pro 月度 | Pro 年度 | Pro 永久 | 无限习惯、每日目标、暂停和专属宠物 |
| ja | Pro 月額 | Pro 年額 | Pro 買い切り | 習慣無制限、目標、一時停止、限定ペット |
| ko | Pro 월간 | Pro 연간 | Pro 평생 | 무제한 습관, 목표, 일시 정지, 전용 펫 |
| hi | Pro मासिक | Pro वार्षिक | Pro आजीवन | असीमित आदतें, लक्ष्य, विराम और ख़ास पेट |

Минимум нужны en-US и ru. Остальные можно добавить потом.

## Первая отправка

Первые покупки уходят на ревью только вместе с версией приложения. На странице версии 1.0 в блоке **In-App Purchases and Subscriptions** нажми "+" и выбери все три товара, иначе ревьюер их не увидит и приложение могут отклонить.

## Проверка до ревью

В TestFlight покупки работают в песочнице и деньги не списываются. Открой Настройки -> Трекер привычек Pro, купи месяц, затем нажми "Восстановить покупки". Подписка в песочнице длится несколько минут.
