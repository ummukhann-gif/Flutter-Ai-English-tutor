
import { useState, useEffect } from 'react';

function useLocalStorage<T>(key: string, initialValue: T): [T, (value: T | ((val: T) => T)) => void] {
  const [storedValue, setStoredValue] = useState<T>(() => {
    try {
      const item = window.localStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch (error) {
      console.error(error);
      return initialValue;
    }
  });

  const setValue = (value: T | ((val: T) => T)) => {
    try {
      // Check if the new value is a function (the functional update form)
      if (value instanceof Function) {
        setStoredValue(prevState => {
          // Calculate the new state based on the previous state
          const newState = value(prevState);
          // Save the new state to localStorage
          window.localStorage.setItem(key, JSON.stringify(newState));
          // Return the new state for React to update
          return newState;
        });
      } else {
        // The new value is a direct value, not a function
        const valueToStore = value;
        setStoredValue(valueToStore);
        window.localStorage.setItem(key, JSON.stringify(valueToStore));
      }
    } catch (error) {
      console.error(error);
    }
  };

  useEffect(() => {
    const handleStorageChange = (e: StorageEvent) => {
      if (e.key === key) {
        try {
          setStoredValue(e.newValue ? JSON.parse(e.newValue) : initialValue);
        } catch (error) {
          console.error(error);
        }
      }
    };
    window.addEventListener('storage', handleStorageChange);
    return () => window.removeEventListener('storage', handleStorageChange);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, initialValue]);

  return [storedValue, setValue];
}

export default useLocalStorage;