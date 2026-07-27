import { darkColors, lightColors } from './colors';
import { radius, spacing, touchTarget } from './spacing';
import { typography } from './typography';

export type ColorTokens = typeof lightColors | typeof darkColors;

export interface AppTheme {
  colors: ColorTokens;
  dark: boolean;
  radius: typeof radius;
  spacing: typeof spacing;
  touchTarget: typeof touchTarget;
  typography: typeof typography;
}

export const lightTheme: AppTheme = {
  colors: lightColors,
  dark: false,
  radius,
  spacing,
  touchTarget,
  typography,
};

export const darkTheme: AppTheme = {
  colors: darkColors,
  dark: true,
  radius,
  spacing,
  touchTarget,
  typography,
};
