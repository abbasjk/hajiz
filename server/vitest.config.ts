import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // الاختبارات تتشارك قاعدة بيانات واحدة
    fileParallelism: false,
  },
});
