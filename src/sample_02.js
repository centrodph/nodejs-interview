// ejercicio 02

const mockData = { age: 18 };

function checkAge(data) {
  if (data === mockData) {
    return 'You are an adult!';
  } else if (data == mockData) {
    return 'You are still an adult.';
  } else {
    return `Hmm.. You don't have an age I guess`;
  }
}

console.log(checkAge({ age: 18 }));

// Que es lo que se imprime y porque?
