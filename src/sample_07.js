function delayedValue() {
  return new Promise((resolve) => setTimeout(() => resolve(42), 100));
}

(async () => {
  console.log("Before");
  const result = delayedValue();
  console.log("After");
  console.log(await result);
})();

// cual es el print y porque
