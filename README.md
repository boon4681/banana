# Banana

Me try to build UI runtime.

Some what of a stupid man myself to build this.

banana compiler emit weird odin cuz odin doesn't have closures, every procedure has isolated stack frames make it hard to passing variables around.
So banana emit odin with Context object and passing it around to every function that needs to access variables.

Security? f*ck that who cares. In this current stage of the project just drop security.

### Why use odin?

Cuz i just want a language ready to go, rust is just a pain in the ass slow shit and rust-analyzer is slow as f*ck, and i need to use a lot of c-lib and rust is not gonna cut it with their unsafe pain that ghost me.

Golang? too painful to use with c-lib.

C? f*ck that i hate c, c is a good language btw but to use for this project, Nah.
