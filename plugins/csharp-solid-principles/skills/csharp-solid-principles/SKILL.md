---
name: csharp-solid-principles
description: C# 예제로 SOLID 원칙을 점검하는 체크리스트. 클래스 설계를 리뷰하거나 코드를 리팩터링할 때, 또는 사용자가 단일 책임(SRP), 개방/폐쇄(OCP), 리스코프 치환(LSP), 인터페이스 분리(ISP), 의존성 역전(DIP)에 대해 물을 때 사용한다. "SOLID 점검해줘", "이 클래스가 너무 많은 일을 하나?", "이 인터페이스 너무 큰 것 같아", "테스트 가능하게 만들려면?" 같은 요청에 대응한다.
---

# C# SOLID 원칙 스킬

C# 코드에서 SOLID 원칙을 점검하고 적용한다.

## 언제 사용하는가
- 사용자가 "SOLID 점검", "SOLID 리뷰", "이 클래스 너무 많은 일 하는 거 아냐?"라고 할 때
- 클래스 설계를 리뷰할 때
- 큰 클래스를 리팩터링할 때
- 설계 관점의 코드 리뷰

---

## 빠른 참조

| 약자 | 원칙 | 한 줄 요약 |
|--------|-----------|-----------|
| **S** | 단일 책임 (Single Responsibility) | 한 클래스 = 변경 이유 하나 |
| **O** | 개방/폐쇄 (Open/Closed) | 확장에는 열려 있고, 수정에는 닫혀 있게 |
| **L** | 리스코프 치환 (Liskov Substitution) | 하위 타입은 상위 타입을 대체할 수 있어야 |
| **I** | 인터페이스 분리 (Interface Segregation) | 하나의 범용 인터페이스보다 여러 개의 구체적 인터페이스 |
| **D** | 의존성 역전 (Dependency Inversion) | 구현이 아니라 추상화에 의존 |

---

## S - 단일 책임 원칙 (SRP)

> "클래스는 변경할 이유가 오직 하나여야 한다."

### 위반 예시

```csharp
// ❌ 나쁨: UserService 가 너무 많은 일을 한다
public class UserService
{
    private readonly AppDbContext _dbContext;
    private readonly IEmailClient _emailClient;
    private readonly IAuditLog _auditLog;

    public User CreateUser(string name, string email)
    {
        // 검증 로직
        if (email is null || !email.Contains('@'))
        {
            throw new ArgumentException("잘못된 이메일");
        }

        // 영속화 로직
        var user = new User(name, email);
        _dbContext.Users.Add(user);
        _dbContext.SaveChanges();

        // 알림 로직
        var subject = "환영합니다!";
        var body = $"안녕하세요 {name} 님";
        _emailClient.Send(email, subject, body);

        // 감사 로그 로직
        _auditLog.Log($"사용자 생성됨: {email}");

        return user;
    }
}
```

**문제점:**
- 검증 규칙이 바뀌면? UserService 수정
- 이메일 템플릿이 바뀌면? UserService 수정
- 감사 로그 형식이 바뀌면? UserService 수정
- 각 관심사를 따로 테스트하기 어려움

### 리팩터링 후

```csharp
// ✅ 좋음: 각 클래스가 하나의 책임만 가진다

public class UserValidator
{
    public void Validate(string name, string email)
    {
        if (email is null || !email.Contains('@'))
        {
            throw new ValidationException("잘못된 이메일");
        }
    }
}

public class UserRepository
{
    private readonly AppDbContext _dbContext;

    public UserRepository(AppDbContext dbContext) => _dbContext = dbContext;

    public User Save(User user)
    {
        _dbContext.Users.Add(user);
        _dbContext.SaveChanges();
        return user;
    }
}

public class WelcomeEmailSender
{
    private readonly IEmailClient _emailClient;

    public WelcomeEmailSender(IEmailClient emailClient) => _emailClient = emailClient;

    public void SendWelcome(User user)
    {
        var subject = "환영합니다!";
        var body = $"안녕하세요 {user.Name} 님";
        _emailClient.Send(user.Email, subject, body);
    }
}

public class UserAuditLogger
{
    private readonly IAuditLog _auditLog;

    public UserAuditLogger(IAuditLog auditLog) => _auditLog = auditLog;

    public void LogCreation(User user)
    {
        _auditLog.Log($"사용자 생성됨: {user.Email}");
    }
}

public class UserService
{
    private readonly UserValidator _validator;
    private readonly UserRepository _repository;
    private readonly WelcomeEmailSender _emailSender;
    private readonly UserAuditLogger _auditLogger;

    public UserService(
        UserValidator validator,
        UserRepository repository,
        WelcomeEmailSender emailSender,
        UserAuditLogger auditLogger)
    {
        _validator = validator;
        _repository = repository;
        _emailSender = emailSender;
        _auditLogger = auditLogger;
    }

    public User CreateUser(string name, string email)
    {
        _validator.Validate(name, email);
        var user = _repository.Save(new User(name, email));
        _emailSender.SendWelcome(user);
        _auditLogger.LogCreation(user);
        return user;
    }
}
```

### SRP 위반을 감지하는 법

- 서로 다른 도메인의 `using` 문이 많다
- 클래스 이름에 "And", "Manager", "Handler" 가 들어간다 (자주 그렇다)
- 서로 관련 없는 데이터를 다루는 메서드들이 있다
- 한 영역의 변경이 무관한 메서드까지 건드리게 한다
- 클래스 이름을 간결하게 짓기 어렵다

### 빠른 점검 질문

1. "그리고" 없이 한 문장으로 클래스의 목적을 설명할 수 있는가?
2. 서로 다른 이해관계자가 이 클래스의 변경을 요구할 수 있는가?
3. 클래스 필드 대부분을 사용하지 않는 메서드가 있는가?

---

## O - 개방/폐쇄 원칙 (OCP)

> "소프트웨어 요소는 확장에는 열려 있고, 수정에는 닫혀 있어야 한다."

### 위반 예시

```csharp
// ❌ 나쁨: 새 할인 종류를 추가하려면 클래스를 수정해야 한다
public class DiscountCalculator
{
    public decimal Calculate(Order order, string discountType)
    {
        if (discountType == "PERCENTAGE")
        {
            return order.Total * 0.1m;
        }
        else if (discountType == "FIXED")
        {
            return 50.0m;
        }
        else if (discountType == "LOYALTY")
        {
            return order.Total * order.Customer.LoyaltyRate;
        }
        // 새 할인 종류가 생길 때마다 = 이 클래스를 수정
        return 0m;
    }
}
```

### 리팩터링 후

```csharp
// ✅ 좋음: 기존 코드 수정 없이 새 할인을 추가

public interface IDiscountStrategy
{
    decimal Calculate(Order order);
    bool Supports(string discountType);
}

public class PercentageDiscount : IDiscountStrategy
{
    public decimal Calculate(Order order) => order.Total * 0.1m;

    public bool Supports(string discountType) => discountType == "PERCENTAGE";
}

public class FixedDiscount : IDiscountStrategy
{
    public decimal Calculate(Order order) => 50.0m;

    public bool Supports(string discountType) => discountType == "FIXED";
}

public class LoyaltyDiscount : IDiscountStrategy
{
    public decimal Calculate(Order order) => order.Total * order.Customer.LoyaltyRate;

    public bool Supports(string discountType) => discountType == "LOYALTY";
}

// 새 할인? 새 클래스만 추가하면 되고, 기존 코드 수정은 필요 없다
public class SeasonalDiscount : IDiscountStrategy
{
    public decimal Calculate(Order order) => order.Total * 0.2m;

    public bool Supports(string discountType) => discountType == "SEASONAL";
}

public class DiscountCalculator
{
    private readonly IEnumerable<IDiscountStrategy> _strategies;

    public DiscountCalculator(IEnumerable<IDiscountStrategy> strategies)
    {
        _strategies = strategies;
    }

    public decimal Calculate(Order order, string discountType)
    {
        return _strategies
            .FirstOrDefault(s => s.Supports(discountType))
            ?.Calculate(order) ?? 0m;
    }
}
```

### OCP 위반을 감지하는 법

- 시간이 지나며 계속 늘어나는 타입/상태 기반 `if/else` 나 `switch`
- 값이 자주 추가되는 enum 기반 분기
- 변경할 때마다 핵심 클래스를 수정해야 함

### 자주 쓰는 OCP 패턴

| 패턴 | 사용 시점 |
|---------|----------|
| Strategy | 같은 연산에 여러 알고리즘이 필요할 때 |
| Template Method | 구조는 같고 단계만 다를 때 |
| Decorator | 동적으로 동작을 추가할 때 |
| Factory | 클래스를 명시하지 않고 객체를 생성할 때 |

---

## L - 리스코프 치환 원칙 (LSP)

> "하위 타입은 상위 타입을 대체할 수 있어야 한다."

### 위반 예시

```csharp
// ❌ 나쁨: Square 가 Rectangle 의 계약을 위반한다
public class Rectangle
{
    protected int Width;
    protected int Height;

    public virtual void SetWidth(int width)
    {
        Width = width;
    }

    public virtual void SetHeight(int height)
    {
        Height = height;
    }

    public int GetArea() => Width * Height;
}

public class Square : Rectangle
{
    public override void SetWidth(int width)
    {
        Width = width;
        Height = width;  // 기대되는 동작을 위반!
    }

    public override void SetHeight(int height)
    {
        Width = height;  // 기대되는 동작을 위반!
        Height = height;
    }
}

// 이 테스트는 Square 에서 실패한다!
void TestRectangle(Rectangle r)
{
    r.SetWidth(5);
    r.SetHeight(4);
    Debug.Assert(r.GetArea() == 20);  // Square 는 16 을 반환!
}
```

### 리팩터링 후

```csharp
// ✅ 좋음: 추상화를 분리한다

public interface IShape
{
    int GetArea();
}

public class Rectangle : IShape
{
    private readonly int _width;
    private readonly int _height;

    public Rectangle(int width, int height)
    {
        _width = width;
        _height = height;
    }

    public int GetArea() => _width * _height;
}

public class Square : IShape
{
    private readonly int _side;

    public Square(int side)
    {
        _side = side;
    }

    public int GetArea() => _side * _side;
}
```

### LSP 규칙

| 규칙 | 의미 |
|------|---------|
| 사전 조건 (Preconditions) | 하위 클래스가 더 강화(더 많이 요구)할 수 없다 |
| 사후 조건 (Postconditions) | 하위 클래스가 더 약화(덜 보장)할 수 없다 |
| 불변식 (Invariants) | 하위 클래스는 상위의 불변식을 유지해야 한다 |
| 이력 (History) | 하위 클래스는 상속받은 상태를 예상 밖으로 바꿀 수 없다 |

### LSP 위반을 감지하는 법

- 하위 클래스가 상위에는 없는 예외를 던진다
- 상위는 객체를 반환하는데 하위는 null 을 반환한다
- 하위 클래스가 상위의 동작을 예상 밖으로 무시하거나 재정의한다
- 메서드 호출 전에 `is`/`as` 타입 검사를 한다
- 인터페이스 메서드가 비어 있거나 예외만 던진다

### 빠른 점검

```csharp
// 이런 코드가 보이면 LSP 위반일 수 있다
if (bird is Penguin)
{
    // fly() 를 호출하지 말 것
}
else
{
    bird.Fly();
}
```

---

## I - 인터페이스 분리 원칙 (ISP)

> "클라이언트는 자신이 사용하지 않는 인터페이스에 의존하도록 강요받아서는 안 된다."

### 위반 예시

```csharp
// ❌ 나쁨: 뚱뚱한 인터페이스가 불필요한 구현을 강요한다
public interface IWorker
{
    void Work();
    void Eat();
    void Sleep();
    void AttendMeeting();
    void WriteReport();
}

// 로봇은 먹거나 잘 수 없다!
public class Robot : IWorker
{
    public void Work() { /* OK */ }
    public void Eat() { /* 먹을 수 없다! */ }
    public void Sleep() { /* 잘 수 없다! */ }
    public void AttendMeeting() { /* OK */ }
    public void WriteReport() { /* 아마도 */ }
}

// 인턴은 회의에 참석하거나 보고서를 쓰지 않는다
public class Intern : IWorker
{
    public void Work() { /* OK */ }
    public void Eat() { /* OK */ }
    public void Sleep() { /* OK */ }
    public void AttendMeeting() { /* 허용되지 않음! */ }
    public void WriteReport() { /* 기대되지 않음! */ }
}
```

### 리팩터링 후

```csharp
// ✅ 좋음: 인터페이스를 분리한다

public interface IWorkable
{
    void Work();
}

public interface IFeedable
{
    void Eat();
    void Sleep();
}

public interface IManageable
{
    void AttendMeeting();
    void WriteReport();
}

// 필요한 것만 조합한다
public class Employee : IWorkable, IFeedable, IManageable
{
    public void Work() { /* ... */ }
    public void Eat() { /* ... */ }
    public void Sleep() { /* ... */ }
    public void AttendMeeting() { /* ... */ }
    public void WriteReport() { /* ... */ }
}

public class Robot : IWorkable
{
    public void Work() { /* ... */ }
    // 불필요한 메서드가 없다!
}

public class Intern : IWorkable, IFeedable
{
    public void Work() { /* ... */ }
    public void Eat() { /* ... */ }
    public void Sleep() { /* ... */ }
    // 회의/보고서 메서드가 없다!
}
```

### ISP 위반을 감지하는 법

- 빈 메서드나 `throw new NotSupportedException()` 로 채운 구현
- 인터페이스에 메서드가 10개 이상
- 클라이언트마다 완전히 다른 메서드 부분집합을 사용
- 인터페이스 변경이 무관한 구현에까지 영향

### .NET 표준 라이브러리에서의 사례

```csharp
// System.Collections.Generic.IList<T> 도 메서드가 많지만, 컬렉션에서는 용인된다.
// 하지만 직접 만드는 인터페이스는 주의할 것!

// ❌ 대부분의 사용처에는 너무 뚱뚱한 인터페이스
public interface IRepository<T>
{
    T? FindById(long id);
    List<T> FindAll();
    T Save(T entity);
    void Delete(T entity);
    void DeleteById(long id);
    List<T> FindByExample(T example);
    IPagedList<T> FindAll(PageRequest pageable);
    List<T> FindAllById(IEnumerable<long> ids);
    long Count();
    bool ExistsById(long id);
    // ... 20개 더
}

// ✅ 더 나음: 사용 목적별로 분리
public interface IReadRepository<T>
{
    T? FindById(long id);
    List<T> FindAll();
}

public interface IWriteRepository<T>
{
    T Save(T entity);
    void Delete(T entity);
}
```

---

## D - 의존성 역전 원칙 (DIP)

> "고수준 모듈은 저수준 모듈에 의존해서는 안 된다. 둘 다 추상화에 의존해야 한다."

### 위반 예시

```csharp
// ❌ 나쁨: 고수준이 저수준에 직접 의존한다
public class OrderService
{
    private readonly SqlServerOrderRepository _repository;  // 구체 클래스!
    private readonly SmtpEmailSender _emailSender;          // 구체 클래스!

    public OrderService()
    {
        _repository = new SqlServerOrderRepository();  // 강한 결합
        _emailSender = new SmtpEmailSender();          // 강한 결합
    }

    public void CreateOrder(Order order)
    {
        _repository.Save(order);
        _emailSender.Send(order.CustomerEmail, "주문 확정됨");
    }
}
```

**문제점:**
- 실제 SQL Server 없이는 테스트 불가
- 이메일 제공자를 교체할 수 없음
- OrderService 가 SQL Server, SMTP 세부 사항을 알고 있음

### 리팩터링 후

```csharp
// ✅ 좋음: 추상화에 의존한다

// 추상화 (인터페이스)
public interface IOrderRepository
{
    void Save(Order order);
    Order? FindById(long id);
}

public interface INotificationSender
{
    void Send(string recipient, string message);
}

// 고수준 모듈은 추상화에 의존한다
public class OrderService
{
    private readonly IOrderRepository _repository;
    private readonly INotificationSender _notificationSender;

    // 의존성을 주입받는다
    public OrderService(
        IOrderRepository repository,
        INotificationSender notificationSender)
    {
        _repository = repository;
        _notificationSender = notificationSender;
    }

    public void CreateOrder(Order order)
    {
        _repository.Save(order);
        _notificationSender.Send(order.CustomerEmail, "주문 확정됨");
    }
}

// 저수준 모듈은 추상화를 구현한다
public class SqlServerOrderRepository : IOrderRepository
{
    public void Save(Order order) { /* SQL Server 전용 */ }

    public Order? FindById(long id) { /* SQL Server 전용 */ return null; }
}

public class SmtpEmailSender : INotificationSender
{
    public void Send(string recipient, string message) { /* SMTP 전용 */ }
}

// 목(mock)으로 쉽게 테스트할 수 있다!
public class InMemoryOrderRepository : IOrderRepository
{
    private readonly Dictionary<long, Order> _orders = new();

    public void Save(Order order)
    {
        _orders[order.Id] = order;
    }

    public Order? FindById(long id)
    {
        return _orders.TryGetValue(id, out var order) ? order : null;
    }
}
```

### DIP with ASP.NET Core

```csharp
// ASP.NET Core 의 내장 DI 컨테이너가 의존성 주입을 자동으로 처리한다

// Program.cs — 서비스 등록
builder.Services.AddScoped<IOrderRepository, EfCoreOrderRepository>();

if (builder.Environment.IsProduction())
{
    builder.Services.AddScoped<INotificationSender, SmtpEmailSender>();
}
else
{
    builder.Services.AddScoped<INotificationSender, MockEmailSender>();
}

builder.Services.AddScoped<OrderService>();

// 생성자 주입 (권장)
public class OrderService
{
    private readonly IOrderRepository _repository;
    private readonly INotificationSender _notificationSender;

    public OrderService(
        IOrderRepository repository,
        INotificationSender notificationSender)
    {
        _repository = repository;
        _notificationSender = notificationSender;
    }
}

public class EfCoreOrderRepository : IOrderRepository
{
    // EF Core 가 구현을 제공
    public void Save(Order order) { /* ... */ }
    public Order? FindById(long id) { /* ... */ return null; }
}
```

### DIP 위반을 감지하는 법

- 비즈니스 로직 안에서 `new ConcreteClass()`
- `using` 문에 구현 패키지가 들어감 (예: `Microsoft.Data.SqlClient`, `System.Net.Mail`)
- 구현을 쉽게 교체할 수 없음
- 테스트에 실제 인프라(데이터베이스, 네트워크)가 필요함

---

## SOLID 리뷰 체크리스트

코드를 리뷰할 때 확인할 것:

| 원칙 | 질문 |
|-----------|----------|
| **SRP** | 이 클래스에 변경할 이유가 둘 이상 있는가? |
| **OCP** | 새 타입/기능을 추가하면 이 클래스를 수정해야 하는가? |
| **LSP** | 하위 클래스를 상위가 기대되는 모든 곳에서 쓸 수 있는가? |
| **ISP** | 비어 있거나 예외만 던지는 메서드 구현이 있는가? |
| **DIP** | 고수준 코드가 구체 구현에 의존하는가? |

---

## 자주 쓰는 리팩터링 패턴

| 위반 | 리팩터링 |
|-----------|-------------|
| SRP - 신(God) 클래스 | 클래스 추출(Extract Class), 메서드 이동(Move Method) |
| OCP - 타입 분기 | 전략 패턴(Strategy), 팩토리(Factory) |
| LSP - 깨진 상속 | 상속보다 합성(Composition over Inheritance), 인터페이스 추출 |
| ISP - 뚱뚱한 인터페이스 | 인터페이스 분리(Split Interface), 역할 인터페이스(Role Interface) |
| DIP - 강한 결합 | 의존성 주입(Dependency Injection), 추상 팩토리(Abstract Factory) |

---

## 관련 스킬

- `design-patterns` - 구현 패턴 (Factory, Strategy, Observer 등)
- `clean-code` - 코드 수준 원칙 (DRY, KISS, 네이밍)
- `csharp-code-review` - 종합 리뷰 체크리스트
