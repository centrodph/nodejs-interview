function delayedValue() {
  return new Promise((resolve) => setTimeout(() => resolve(42), 100));
}

(async () => {
  console.log("Before");
  const result = await delayedValue();
  console.log(result);
  console.log("After");
})();

// que imprime y porque
