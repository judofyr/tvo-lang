# Tvo

Tvo is a concatenative, functional, object-oriented programming
language.

```
# Concatenative
2 2 + .

# Functional
:square dup * ;
[square] [1 2 3] map  .

# Object-oriented
=Person{
  rec
  :fullname
    dup
    [.firstname " "] dip
    .lastname + +
  ;
}

=me{ Person "Magnus" =firstname  "Holm" =lastname }

me fullname .

```

Note that Tvo includes a little syntax sugar for left-to-right reading:

```
foo{ bar baz }

  is just sugar for

bar baz foo
```

