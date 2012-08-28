# Что это?
Это -- решение тестового задания на вакансию Erlang/OTP-разработчика:
распределённая программа для поиска простых чисел и вывода их в файл.

Многое сделано неидеоматично, потомучто это мой первый опыт использования эрланга.
Модульные тесты (точнее, один тест) очень примитивны.


# Использование

## Компиляция

`$ rebar compile` или `$ erl -make`

## Тестирование

`rebar eunit`

## Конфигурация

Переменная окружения $CONFIG, если установлена, задаёт используемый файл конфигурации.

Конфигурируемые параметры:
* `{debug, boolean()}` : включает / выключает вывод дополнительной информации и задержки при вычислении.
* `{file, filename()}` : имя файла, в который выводится результат.

## Запуск

`./bin/start_master [<max>]` : запуск главного узла; если указан аргумент, то процесс решения запускается автоматически.

`./bin/start_worker <name>` : запуск рабочего узла, `<name>` -- уникальное имя.

Как только подключается хотя бы один рабочий, начинается процесс решения.
Если все рабочие будут отключены, процесс приостановится до подключения нового рабочего.
Иногда бывает, что рабочий не может подключиться к главному узлу --
в этом случае можно попробовать запустить его ещё раз или перезапустить главный узел.

