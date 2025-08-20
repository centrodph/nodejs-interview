// ejercicio 03 
// leer el archivo sample.txt y cambiar el texto `devmode` por "HelloWorld"
// generar un log result.txt 
// con la cantidad de veces que se repite el texto "devmode"
// un listatado de los numero de lineas que contienen el texto "devmode"

/**
 * Sample 03 - Streaming replace and logging
 *
 * This script reads the `sample.txt` file line-by-line using a streaming approach
 * to minimize memory usage for large files. It replaces every occurrence of the
 * exact text `devmode` with `HelloWorld`, keeps track of how many replacements
 * were made, and records the line numbers that contained the original text.
 *
 * Results are written to `result.txt`, and the original `sample.txt` is updated
 * atomically by writing to a temporary file and then renaming it back.
 *
 * Logging is printed to the console to aid visibility and debugging. All user-facing
 * logs and documentation are in English to keep consistency with coding standards.
 */

import fs from 'node:fs';
import fsPromises from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import readline from 'node:readline';

/** Absolute path to the current directory of this module (i.e., `src/`). */
const currentModuleDirectory = path.dirname(fileURLToPath(import.meta.url));

/** File names and derived absolute paths. */
const inputFileName = 'sample.txt';
const temporaryFileName = 'sample.tmp';
const logFileName = 'result.txt';

const inputFilePath = path.join(currentModuleDirectory, inputFileName);
const temporaryFilePath = path.join(currentModuleDirectory, temporaryFileName);
const logFilePath = path.join(currentModuleDirectory, logFileName);

/**
 * Counts how many times a substring appears in a string.
 *
 * The search is case-sensitive and does not overlap (consistent with typical
 * text replacement semantics using a global regex or replaceAll).
 *
 * @param {string} haystack - The source string to search in.
 * @param {string} needle - The exact substring to count.
 * @returns {number} The number of non-overlapping occurrences.
 */
function countNonOverlappingOccurrences(haystack, needle) {
  if (needle.length === 0) {
    return 0;
  }

  let count = 0;
  let searchIndex = 0;

  // Iterate until indexOf can no longer find the needle
  while (true) {
    const foundAtIndex = haystack.indexOf(needle, searchIndex);
    if (foundAtIndex === -1) {
      break; // No more occurrences
    }
    count += 1;
    // Move past the current match to avoid overlap counting
    searchIndex = foundAtIndex + needle.length;
  }

  return count;
}

/**
 * Writes the log file describing the transformation results.
 *
 * @param {Object} params - The parameters object.
 * @param {string} params.sourceFilePath - Absolute path to the original input file.
 * @param {string} params.logOutputPath - Absolute path to the log output file.
 * @param {number} params.totalOccurrencesCount - Total number of occurrences replaced.
 * @param {number[]} params.matchedLineNumbers - One-based line numbers that contained the original text.
 * @returns {Promise<void>} Resolves when the log file has been fully written.
 */
async function writeResultLog({
  sourceFilePath,
  logOutputPath,
  totalOccurrencesCount,
  matchedLineNumbers,
}) {
  const logTimestamp = new Date().toISOString();

  // Prepare a human-readable, deterministic log format.
  const logContents = [
    `Timestamp: ${logTimestamp}`,
    `Source file: ${sourceFilePath}`,
    `Occurrences replaced ("devmode" -> "HelloWorld"): ${totalOccurrencesCount}`,
    `Lines containing original text (1-based): ${matchedLineNumbers.length > 0 ? matchedLineNumbers.join(', ') : '(none)'}`,
    '',
  ].join('\n');

  await fsPromises.writeFile(logOutputPath, logContents, { encoding: 'utf8' });
}

/**
 * Processes the input file by replacing occurrences and generating the result log.
 * Uses streaming to avoid high memory usage on large inputs.
 *
 * @param {string} sourceFilePath - Absolute path to the input file.
 * @param {string} tempFilePath - Absolute path to the temporary output file.
 * @param {string} logOutputPath - Absolute path to the log file.
 * @returns {Promise<void>} Resolves when processing completes successfully.
 */
async function processFileAndGenerateLog(sourceFilePath, tempFilePath, logOutputPath) {
  console.log('Starting streaming replacement for file:', sourceFilePath);

  // Validate that the source file exists before proceeding.
  try {
    await fsPromises.access(sourceFilePath, fs.constants.R_OK);
  } catch {
    throw new Error(`Input file not found or not readable: ${sourceFilePath}`);
  }

  // Create read and write streams for streaming line-by-line processing.
  const readStream = fs.createReadStream(sourceFilePath, { encoding: 'utf8' });
  const writeStream = fs.createWriteStream(tempFilePath, { encoding: 'utf8' });

  const lineReader = readline.createInterface({
    input: readStream,
    crlfDelay: Infinity, // Handle both Windows and Unix newlines consistently
  });

  let currentLineNumber = 0; // One-based after increment
  let totalOccurrencesCount = 0;
  const matchedLineNumbers = []; // Records line numbers that contained the original text

  // Iterate over each line from the input stream
  for await (const originalLine of lineReader) {
    currentLineNumber += 1;

    // Count occurrences in this specific line
    const occurrencesInLine = countNonOverlappingOccurrences(originalLine, 'devmode');
    if (occurrencesInLine > 0) {
      totalOccurrencesCount += occurrencesInLine;
      matchedLineNumbers.push(currentLineNumber);
    }

    // Replace all occurrences in the line; use a global regex for clarity
    const replacedLine = originalLine.replace(/devmode/g, 'HelloWorld');

    // Write the transformed line and re-add the newline terminator
    if (!writeStream.write(`${replacedLine}\n`)) {
      // Backpressure: wait for the 'drain' event to continue writing safely
      await new Promise((resolve) => writeStream.once('drain', resolve));
    }
  }

  // Finalize the output stream to ensure all bytes are flushed
  await new Promise((resolve, reject) => {
    writeStream.end(() => resolve());
    writeStream.on('error', reject);
  });

  console.log('Finished writing temporary file:', tempFilePath);

  // Atomically replace the original file by renaming the temporary file
  await fsPromises.rename(tempFilePath, sourceFilePath);
  console.log('Replaced original file with updated content:', sourceFilePath);

  // Write the result log with counts and line numbers
  await writeResultLog({
    sourceFilePath,
    logOutputPath,
    totalOccurrencesCount,
    matchedLineNumbers,
  });

  console.log('Wrote result log to:', logOutputPath);
  console.log('Total occurrences replaced:', totalOccurrencesCount);
  if (matchedLineNumbers.length > 0) {
    console.log('Lines containing the original text:', matchedLineNumbers.join(', '));
  } else {
    console.log('No lines contained the original text.');
  }
}

/**
 * Entrypoint: orchestrates the processing and handles fatal errors.
 *
 * This function is invoked immediately so the script runs when executed with Node.js.
 */
async function main() {
  try {
    await processFileAndGenerateLog(inputFilePath, temporaryFilePath, logFilePath);
  } catch (error) {
    // Attempt to clean up the temporary file if something went wrong.
    try {
      await fsPromises.unlink(temporaryFilePath);
      // Note: unlink may fail if the file never existed or was already removed. That is fine.
    } catch {}

    console.error('Fatal error while processing the file:', error);
    // Exit with non-zero code to signal failure when run in CI or scripts
    process.exitCode = 1;
  }
}

// Execute when run directly.
// In ESM, we check whether this module URL matches the first CLI argument as a best-effort signal.
const executedScriptUrl = pathToFileURL(process.argv[1] ?? '').href;
if (import.meta.url === executedScriptUrl) {
  // eslint-disable-next-line no-console
  console.log('Executing Sample 03 script...');
  main();
}





