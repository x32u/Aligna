import { Stack } from 'expo-router';

export default function AppLayout() {
  return (
    <Stack screenOptions={{ headerShown: false, animation: 'slide_from_right' }}>
      <Stack.Screen name="dashboard" />
      <Stack.Screen name="meeting" />
      <Stack.Screen name="results" />
      <Stack.Screen name="timeline" />
    </Stack>
  );
}
