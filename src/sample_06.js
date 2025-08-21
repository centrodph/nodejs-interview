// ejercicio 06 (minimal)
// Run the script and explain the output
// 1. What is the output?
// 2. What is the time complexity of the script?
// 3. What is the space complexity of the script?
// 4. What is a way to improve the script?
// 5. Log the memory usage of the script

import { jsonResponse } from "./json_response.js";

function processItem(item) {
  const result = Math.pow(item * 4, 2);
  console.log(result);
  return result;
}

for (let i = 0; i < jsonResponse.length; i++) {
  processItem(jsonResponse[i]);
}
