create schema if not exists hashids;

create or replace function hashids.to_alphabet(
  number bigint,
  alphabet varchar
) returns text as $$
declare
  id text := '';
  current_number bigint := number;
  alphabet_arr varchar [] := regexp_split_to_array( alphabet, '' );
  alphabet_length integer := length( alphabet );
begin
  while current_number > 0 loop
    id := alphabet_arr [( current_number % alphabet_length ) + 1] || id;
    current_number := current_number / alphabet_length;
  end loop;

  return id;
end;
$$ language plpgsql;

create or replace function hashids.from_alphabet(
  id varchar,
  alphabet varchar,
  out number bigint
) as $$
declare
  alphabet_arr varchar [] := regexp_split_to_array( alphabet, '' );
  parts varchar [] := regexp_split_to_array( id, '' );
  parts_length integer := array_length( parts, 1 );
  letter varchar;
  letter_position integer;
begin
  number := 0;

  for i in 1..parts_length loop
    letter := parts [i];
    letter_position := array_position( alphabet_arr, letter ) - 1;

    number := number * length( alphabet ) + letter_position;
  end loop;
end;
$$ language plpgsql;

create or replace function hashids.shuffle(
  alphabet varchar = '',
  salt varchar = ''
) returns varchar as $$
declare
  alphabet_arr varchar [] := regexp_split_to_array( alphabet, '' );
  alphabet_length integer := length( alphabet );
  char_position integer := 1;
  shuffle_v integer := 0;
  shuffle_p integer := 0;
  shuffle_j integer := 0;
  shuffle_integer integer := 0;
  shuffle_tmp varchar;
  salt_char varchar;
  old_position integer;
  new_position integer;
begin
  if length( salt ) < 1 then
    return alphabet;
  end if;

  for i in reverse ( alphabet_length - 1 )..1 loop
    shuffle_v := shuffle_v % length( salt );
    char_position := shuffle_v + 1;

    salt_char := substr( salt, char_position, 1 );
    shuffle_integer := ascii( salt_char );
    shuffle_p = shuffle_p + shuffle_integer;
    shuffle_j = ( shuffle_integer + shuffle_v + shuffle_p ) % i;

    old_position = shuffle_j + 1;
    new_position = i + 1;

    shuffle_tmp = alphabet_arr [new_position];

    alphabet_arr [new_position] = alphabet_arr [old_position];
    alphabet_arr [old_position] = shuffle_tmp;
    shuffle_v := ( shuffle_v + 1 );
  end loop;

  return array_to_string( alphabet_arr, '' );
end;
$$ language plpgsql;

create or replace function hashids.split( id varchar = '', separators varchar = '', out parts varchar [] ) as $$
begin
  if length( separators ) < 1 then
    parts := '{}' :: varchar [];
  else
    parts := regexp_split_to_array( regexp_replace( id, '[' || separators || ']', ' ', 'g' ), ' ' );
  end if;
end;
$$ language plpgsql;

create or replace function hashids.unique_alphabet( in alphabet varchar = '', separators varchar = '', out new_alphabet varchar [] ) as $$
declare
  alphabet_arr varchar [] := regexp_split_to_array( alphabet, '' );
  separators_arr varchar [] := regexp_split_to_array( separators, '' );
  letter varchar;
begin
  new_alphabet := '{}' :: varchar [];

  for i in 1..array_length( alphabet_arr, 1 ) loop
    letter := alphabet_arr [i];

    if (
      array_position( new_alphabet, letter ) is not null or
      array_position( separators_arr, letter ) is not null
    ) then
      continue;
    end if;

    new_alphabet := array_append( new_alphabet, letter );
  end loop;
end;
$$ language plpgsql;

create or replace function hashids._prepare(
  inout alphabet varchar,
  in salt varchar = '',
  out alphabet_arr varchar [],
  out alphabet_length integer,
  out original_alphabet varchar,
  out original_alphabet_arr varchar [],
  out separators varchar,
  out separators_arr varchar [],
  out separators_length integer,
  out guards varchar,
  out guards_length integer
) as $$
declare
  min_alphabet_length integer := 16;
  sep_div integer := 3.5;
  guard_div integer := 12;
  guard_count integer;
  cur_sep varchar;
  diff varchar;
begin
  if alphabet is null then
    alphabet := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890';
  end if;

  original_alphabet := alphabet;
  original_alphabet_arr := regexp_split_to_array( alphabet, '' );
  guards := '';
  separators := 'cfhistuCFHISTU';
  separators_arr := regexp_split_to_array( separators, '' );
  alphabet_arr := hashids.unique_alphabet( alphabet := alphabet, separators := separators );

  alphabet := array_to_string( alphabet_arr, '' );
  alphabet_length := array_length( alphabet_arr, 1 );

  if alphabet_length < min_alphabet_length then
    raise exception '[hash_id] Alphabet must contain at least % unique characters', min_alphabet_length;
  end if;

  if array_position( alphabet_arr, ' ' ) is not null then
    raise exception '[hash_id] error: Alphabet cannot contain spaces';
  end if;

  for i in 1..length( separators ) loop
    cur_sep := array_position( original_alphabet_arr, separators_arr [i] );

    if cur_sep is null then
      separators := substr( separators, 1, i ) || ' ' || substr( separators, i + 1 );
    end if;
  end loop;

  separators := regexp_replace( separators, '[ ]', '', 'g' );
  separators := hashids.shuffle( separators, salt );

  if ( length( separators ) < 1 or ( length( alphabet ) / length( separators ) ) > sep_div ) then
    separators_length = ceil( length( alphabet ) / sep_div );

    if ( separators_length > length( separators ) ) then
      diff := separators_length - length( separators );
      separators := separators || substr( alphabet, 1, diff );
      alphabet := substr( alphabet, diff );
    end if;
  end if;

  alphabet := hashids.shuffle( alphabet, salt );
  guard_count := ceil( length( alphabet ) / guard_div );

  if length( alphabet ) < 3 then
    guards := substr( separators, 1, guard_count );
    separators := substr( separators, guard_count );
  else
    guards := substr( alphabet, 1, guard_count );
    alphabet := substr( alphabet, guard_count + 1 );
  end if;

  alphabet_arr := regexp_split_to_array( alphabet, '' );
  alphabet_length := length( alphabet );
  separators_length := length( separators );
  guards_length := length( guards );
end;
$$ language plpgsql;

create or replace function hashids.encode(
  number anyelement,
  salt varchar = '',
  min_length integer = null,
  alphabet varchar = null
) returns text as $$
declare
  optns record;
  alphabet_arr varchar [];
  alphabet_length int;
  separators_length int;
  guards_length int;
  guard_index integer;
  guards varchar;
  guard varchar = '';
  separators varchar;
  i integer := 0;
  hash_id text := '';
  numbers_id_int bigint := 0;
  numbers bigint [];
  numbers_length integer;
  current_num bigint;
  lottery varchar := '';
  half_length integer;
  excess integer;
  buffer text := '';
  last_id text;
begin
  optns := hashids._prepare( salt := salt, alphabet := alphabet );
  alphabet := optns.alphabet;
  alphabet_arr := optns.alphabet_arr;
  alphabet_length := optns.alphabet_length;
  separators := optns.separators;
  separators_length := optns.separators_length;
  guards := optns.guards;
  guards_length := optns.guards_length;

  if min_length is null then
    min_length := 0;
  end if;

  if number :: text ~ '^\{.*\}$' then -- if number parameter is an array
    numbers := number;
  else
    numbers := array [number];
  end if;

  numbers_length := array_length( numbers, 1 );

  if numbers_length = 0 then
    return hash_id;
  end if;

  for i in 0..numbers_length - 1 loop
    numbers_id_int := numbers_id_int + ( numbers [i + 1] % ( i + 100 ) );
  end loop;

  hash_id := alphabet_arr [( numbers_id_int % alphabet_length ) + 1];
  lottery := hash_id;

  for i in 0..numbers_length - 1 loop
    current_num := numbers [i + 1];
    buffer := lottery || salt || alphabet;

    alphabet := hashids.shuffle( alphabet, substr( buffer, 1, alphabet_length ) );
    last_id := hashids.to_alphabet( current_num, alphabet );

    hash_id := hash_id || last_id;

    if ( i < numbers_length - 1 ) then
      current_num = current_num % ascii( substr( last_id, 1, 1 ) ) + i;
      hash_id := hash_id || substr( separators, ( current_num % separators_length ) :: integer + 1, 1 );
    end if;
  end loop;

  if length( hash_id ) < min_length then
    guard_index := ( numbers_id_int + ascii( substr( hash_id, 1, 1 ) ) ) % guards_length;
    guard := substr( guards, guard_index + 1, 1 );

    hash_id = guard || hash_id;

    if length( hash_id ) < min_length then
      guard_index := ( numbers_id_int + ascii( substr( hash_id, 3, 1 ) ) ) % guards_length;
      guard := substr( guards, guard_index + 1, 1 );

      hash_id := hash_id || guard;
    end if;
  end if;

  half_length = ( length( alphabet ) / 2 );

  while ( length( hash_id ) < min_length ) loop
    alphabet := hashids.shuffle( alphabet, alphabet );
    hash_id := substr( alphabet, half_length + 1 ) || hash_id || substr( alphabet, 1, half_length );

    excess := length( hash_id ) - min_length;

    if excess > 0 then
      hash_id := substr( hash_id, ( excess / 2 ) + 1, min_length );
    end if;
  end loop;

  return hash_id;
end;
$$ language plpgsql;

create or replace function hashids.decode(
  in id varchar,
  in alphabet varchar = null,
  in salt varchar = '',
  in min_length integer = null
) returns bigint [] as $$
declare
  optns record;
  numbers bigint [];
  empty_array bigint [];
  parts varchar [];
  parts_count integer;
  id_breakdown varchar;
  lottery varchar;
  sub_id varchar;
  buffer varchar;
  idx integer := 1;
begin
  numbers := array [] :: bigint [];
  empty_array := numbers;

  if ( id is null or length( id ) = 0 ) then
    return empty_array;
  end if;

  optns := hashids._prepare( salt := salt, alphabet := alphabet );
  alphabet := optns.alphabet;
  parts := hashids.split( id, optns.guards );
  parts_count = array_length( parts, 1 );

  if parts_count = 3 or parts_count = 2 then
    idx := 2;
  end if;

  id_breakdown := parts [idx];

  lottery := substr( id_breakdown, 1, 1 );
  id_breakdown := substr( id_breakdown, 2 );

  parts := hashids.split( id_breakdown, optns.separators );
  parts_count = array_length( parts, 1 );

  for i in 1..parts_count loop
    sub_id := parts [i];
    buffer := lottery || salt || alphabet;

    alphabet := hashids.shuffle( alphabet, substr( buffer, 1, optns.alphabet_length ) );
    numbers := numbers || hashids.from_alphabet( sub_id, alphabet );
  end loop;

  if (
    array_length( numbers, 1 ) = 0 or
    hashids.encode(
        number := numbers,
        alphabet := optns.original_alphabet,
        salt := salt,
        min_length := min_length
    ) is distinct from id
  ) then
    return empty_array;
  end if;

  return numbers;
end;
$$ language plpgsql;

create or replace function hashids.encode_hex(
  hex varchar,
  salt varchar = '',
  min_length integer = null,
  alphabet varchar = null
) returns varchar as $$
declare
  parts varchar [];
  numbers bigint [];
  number bigint;
begin
  if not hex ~ '^[0-9a-fA-F]+$' then
    return '';
  end if;

  execute 'select array(select t[1] from regexp_matches( $1, ''[\w\\W]{1,12}'', ''g'') t)'
  into parts
  using hex;

  for i in 1..array_length( parts, 1 ) loop
    number := ( 'x' || lpad( ( '1' || parts [i] ), 16, '0' ) ) :: bit( 64 ) :: bigint;
    numbers := array_append( numbers, number );
  end loop;

  return hashids.encode( number := numbers, salt := salt, min_length := min_length, alphabet := alphabet );
end;
$$ language plpgsql;

create or replace function hashids.decode_hex(
  id varchar,
  salt varchar = '',
  min_length integer = null,
  alphabet varchar = null
) returns varchar as $$
declare
  hex varchar = '';
  numbers bigint [];
begin
  numbers := hashids.decode( id := id, salt := salt, min_length := min_length, alphabet := alphabet );

  for i in 1..array_length( numbers, 1 ) loop
    hex := hex || substr( to_hex( numbers [i] ), 2 );
  end loop;

  return hex;
end;
$$ language plpgsql;

-- select hashids.encode( number := 999, min_length := 6, salt := 'salt');
-- select hashids.decode( id := 'dkrMl8', min_length := 6, salt := 'salt');
-- select hashids.encode_hex( hex := '507f1f77bcf86cd799439011', salt := 'salt');
-- select hashids.decode_hex( id := 'zro2yr9M4ZCzZ9zd9xYv', salt := 'salt');
