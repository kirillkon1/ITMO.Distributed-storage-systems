#!/bin/bash
database='studs'
f=0
while [ $f -eq 0 ]; do
  read -p 'Название таблицы: ' table
  IFS='.'
  read -a strarr <<<"$table"
  count=${#strarr[@]}

  if [ "$count" -lt 1 ] || [ "$count" -gt 3 ]; then
    echo "Данные введены некорректно. Повторите снова"
    continue
  fi
  # Database.scheme.table
  #------------------------------------------------

  if [ "$count" -eq 3 ]; then
    database_tmp=${strarr[0]}

    check=$(psql -h pg -d studs -t -c "select count(*) from pg_database where datname = '$database_tmp'")

    if [ $check -ne 1 ]; then
      echo "База данных ($database_tmp) не была найдена. Повторите попытку."
      continue
    fi
    database=$database_tmp
    scheme="${strarr[1]}"

    check=$(psql -h pg -d studs -t -c "select count(*) from pg_namespace where nspname = '$scheme'")
    if [ "$check" -ne 1 ]; then
      echo "Схема ($scheme) не была найдена. Повторите попытку."
      continue
    fi

    table="${strarr[2]}"

    check=$(psql -h pg -d studs -t -c "select count(*) from pg_namespace where
        oid in (select relnamespace from pg_class where relname = '$table') and
        nspname='$scheme'")
    if [ "$check" -ne 1 ]; then
      echo "Таблица ($table) не была найдена."
      continue
    fi
    echo "check 3 args"
    f=1
  fi


  # scheme.table
  #------------------------------------------------

  if [ $count -eq 2 ]; then
    scheme=${strarr[0]}
    table=${strarr[1]}

    check=$(psql -h pg -d studs -t -c "select count(*) from pg_namespace where nspname = '$scheme'")
    if [ $check -ne 1 ]; then
      echo "Схема ($scheme) не была найдена. Повторите попытку."
      continue
    fi

    check=$(psql -h pg -d studs -t -c "select count(*) from pg_namespace where
    oid in (select relnamespace from pg_class where relname = '$table') and
    nspname='$scheme'")
    if [ $check -ne 1 ]; then
      echo "Таблица ($table) не была найдена."
      continue
    fi
    echo "check 2 args"
    f=1
  fi

  # table
  #------------------------------------------------

  if [[ $count -eq 1 ]]; then

    tablecount=$(psql -h pg -d studs -t -c "select count(*) from pg_class where
relname = '$table'")
    echo 'Найдено таблиц с таким названием: '"$tablecount"

    while [[ $tablecount -lt 1 ]]; do
      echo 'такой таблицы нет'
      read -p 'Название таблицы: ' table
      tablecount=$(psql -h pg -d studs -t -c "select count(*) from pg_class where
relname = '$table'")
    done

    if [[ $tablecount -eq 1 ]]; then
      scheme=$(psql -h pg -d studs -t -c "select nspname from pg_namespace where
oid in (select relnamespace from pg_class where relname = '$table')")
    fi

    if [[ $tablecount -gt 1 ]]; then
      echo 'Выберите пользователя'
      psql -h pg -d studs -t -c "select nspname from pg_namespace where oid in
            (select relnamespace from pg_class where relname = '$table' limit 50)"

      while [[ $f -eq 0 ]]; do
        read -p 'Пользователь: ' scheme
        check=$(psql -h pg -d studs -t -c "select count(*) from pg_namespace where
                oid in (select relnamespace from pg_class where relname = '$table') and
                nspname='$scheme'")
        if [[ $check -eq 1 ]]; then
          f=1
        fi
      done

    fi
  fi

done

user=${scheme}

#Запуск скрипта
psql -h pg -d "$database" -c "
create or replace function task(user_schema text, table_name text) returns void
as
\$\$
declare
    rec            record;
    str_num        text;
    str_attname    text;
    str_typename   text;
    str_constrname text;
    str_tmp        text;
    f              record;
    b              bool;
    str_type       text;
    str_constr     text;

begin

    str_type = rpad('Type', 8, ' ');
    str_constr = rpad('Constr', 8, ' ');

    raise info 'Пользователь: %', user_schema;
    raise info 'Таблица: % ', table_name;
    raise info ' ';

    RAISE INFO '% % %', rpad('No.', 3, ' '), rpad('Имя столбца', 28, ' '), rpad('Аттрибуты', 15, ' ');
    RAISE INFO '% % %', rpad('', 3, '-'), rpad('', 28, '-'), rpad('', 30, '-');
    str_tmp = '';
    b = false;
    for rec in (select attnum,    --Порядковый номер столбца
                       attname,   --Имя столбца
                       typname,   --Имя типа данных
                       conname,   --Имя ограничения
                       contype,   --Тип ограничения
                       confrelid, --Если это внешний ключ, таблица, на которую он ссылается; иначе 0
                       confkey,   --Для внешнего ключа определяет список столбцов, на которые он ссылается
                       relname,   --Имя (в данном примере имя Таблицы)
                       atttypmod  --Доп число для опред. типа данных. Напр. ограничение длины для varchar.
                from pg_attribute
                         join pg_type on pg_type.oid = atttypid
                         left join pg_constraint on (pg_attribute.attnum =
                    any (pg_constraint.conkey) and attrelid = conrelid)
                         left join pg_class on pg_class.oid = confrelid
                where attrelid = (select oid
                                  from pg_class
                                  where relnamespace = (select oid
                                                        from pg_namespace
                                                        where pg_namespace.nspname = user_schema)
                                    and relname = table_name)
                  and attnum > 0
                order by attnum)
        loop
            str_num = rpad(rec.attnum::text, 3, ' ');
            str_attname = rpad(rec.attname, 28, ' ');

            if rec.atttypmod > -1 then
                str_typename = rpad(rec.typname || '(' || rec.atttypmod || ')', 15, ' ');
            else
                str_typename = rpad(rec.typname, 15, ' ');
            end if;

            if rec.conname is not null then
                            if rec.contype = 'p' then
                                str_constrname = lpad(' ', 31, E'\u00A0') || ' ' || str_constr || ':' ||
                                                 ' \"' || rec.conname || '\"' || ' Primary Key';
                            end if;
                            if rec.contype = 'f' then
                                str_constrname = lpad(' ', 31, E'\u00A0') || ' ' || str_constr || ':' ||
                                                 ' \"' || rec.conname || '\"' || ' References ' || rec.relname;
                    for f in (select attnum, attname
                              from pg_attribute
                                       join pg_class on
                                  pg_attribute.attrelid = pg_class.oid
                              where attrelid = rec.confrelid)
                        loop
                            if f.attnum = ANY (rec.confkey) then
                                if b = false then
                                    str_tmp = str_tmp || f.attname;
                                    b = true;
                                else
                                    str_tmp = str_tmp || ',' || f.attname;
                                end if;
                            end if;
                        end loop;
                    str_constrname = str_constrname || '(' || str_tmp || ')' || E'\n';
                end if;
                raise info '% % %: %', str_num, str_attname,str_type, str_typename;
                raise info ' %', str_constrname;
                raise info ' ';
            else
                raise info '% % %: %', str_num, str_attname, str_type, str_typename;
            end if;
        end loop;
end

\$\$ language plpgsql;

select task('$user', '$table');

drop function task(text,text);

"

