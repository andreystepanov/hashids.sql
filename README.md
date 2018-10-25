# PL/pgSQL implementation of [Hashids](https://hashids.org/)

Hashids is a small open-source library that generates short, unique, non-sequential ids from numbers.
It converts numbers like 347 into strings like “yr8”. You can also decode those ids back. This is useful in bundling several parameters into one or simply using them as short UIDs.

You can use hashids to hide primary keys in your database.

More information about hashids and it's implementations can be found here: [hashids.org](http://hashids.org)

**Suitable for hosted enviroments like AWS RDS**.

*But if you are looking for an PG extention, then please check out [pg_hashids](https://github.com/iCyberon/pg_hashids) repository.*

# Usage
#### Encoding
Returns a hash using the default `alphabet` and specified `min_length` and `salt` parameters.

```sql
select hashids.encode( number := 999, min_length := 6, salt := 'salt'); -- dkrMl8
```

`number` parameter can also be an array of numbers:

```sql
select hashids.encode( number := array[111,222], min_length := 6, salt := 'salt'); -- VyAHPK
```

It's also could be helpful to use it with [sequences](https://www.postgresql.org/docs/current/static/sql-createsequence.html):

```sql
select hashids.encode( number := nextval('schema.sequence_name'), min_length := 6, salt := 'salt');
```
  
You can also decode previously generated hashes. Just use the same parameters `salt`, `min_length` and `alphabet`, otherwise you'll get wrong results.
  
```sql
select hashids.decode( id := 'dkrMl8', min_length := 6, salt := 'salt'); -- {999}
select hashids.decode( id := 'VyAHPK', min_length := 6, salt := 'salt'); -- {111,222}
```

Using custom `alphabet`, only capitalized letters and numbers:
	
```sql
select hashids.encode( number := 999, salt := 'salt', alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'); -- D3Q5
```
  
#### Encode hex instead of numbers

Useful if you want to encode [Mongo](https://www.mongodb.com/)'s ObjectIds. Note that there is no limit on how large of a hex number you can pass (it does not have to be Mongo's ObjectId).

```sql
select hashids.encode_hex( hex := '507f1f77bcf86cd799439011', salt := 'salt'); -- zro2yr9M4ZCzZ9zd9xYv
```
	
These ids can be also easily decoded back to their original values:

```sql
select hashids.decode_hex( id := 'zro2yr9M4ZCzZ9zd9xYv', salt := 'salt'); -- 507f1f77bcf86cd799439011
```
