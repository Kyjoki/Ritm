export class AppError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export const missing = (what: string) =>
  new AppError(404, 'NOT_FOUND', `${what} не найдено. Обновите страницу.`);
export const conflict = (message: string) => new AppError(409, 'CONFLICT', message);
