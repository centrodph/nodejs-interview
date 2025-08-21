// ejercicio 01
const a = { prop: 1 };

const b = a;

b.prop = 2;

console.log(`a.prop -> ${a.prop}`); // ???
console.log(`b.prop -> ${b.prop}`); // ???
// why?

// Cual es el valor de a.prop y b.prop?
// Cuando javascript asigna por valor o por referencia?