create or replace procedure task(user_schema text, user_table text)
as

$$
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
    raise info 'Таблица: % ', user_table;
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
                                    and relname = user_table)
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

$$ language plpgsql;

call task('public', 'users');
