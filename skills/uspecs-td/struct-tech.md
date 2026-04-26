# Domain technology: prod

## Tech stack

- Language: Dart 3.x
- Framework: Flutter 3.x
- State management: BLoC
- Navigation: GoRouter
- Dependency injection: get_it + injectable
- Local storage: Hive
- Backend: Firebase (Auth, Firestore, Cloud Functions)

## Architecture patterns

- MVVM with BLoC as ViewModel layer
- Repository pattern for data access
- Clean architecture layers: presentation -> domain -> data

## Repo layout

```text
lib/
  blocs/           - BLoC state management classes
  data/
    models/        - data models and DTOs
    repositories/  - repository implementations
  domain/          - domain entities and interfaces
  ui/
    {feature}/     - feature-specific screens and widgets
    shared/        - shared UI components
  utils/           - utility classes and helpers
test/
  unit/            - unit tests
  widget/          - widget tests
  integration/     - integration tests
```

## UI/UX guidelines (if applicable)

- Material Design 3
- Responsive layout: mobile-first, tablet breakpoint at 600dp
- Theme: light/dark mode support via ThemeData
- Accessibility: minimum touch target 48x48dp, semantic labels on all interactive elements
